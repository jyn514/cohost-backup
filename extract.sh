#!/usr/bin/env bash
# Download and parse all Cohost posts for the current user
set -euo pipefail

exists () {
    command -v "$1" > /dev/null 2>&1
}

if exists jq.exe; then jq()  { command jq.exe  "$@"; } fi
if exists pup.exe; then pup()  { command pup.exe  "$@"; } fi

die() {
    echo "$@" >&2
    exit 1
}

posts() {
    html=$1
    pup 'script#trpc-dehydrated-state' 'text{}' < $html \
        | jq '.queries[] | .state?.data?.posts? | select(. != null)' 
}

# cohost posts contain 0 or more posts in a chain named "shareTree"; more than 0 indicates this is a quote-post/repost.
# note that cohost does not really distinguish a repost from a quote post without text
extract() {
    # this jq snippet works on a single non-nested post. 
    get_project='{ id: .projectId, handle, displayName }'
    get_one="
        content: .blocks | map(
            if   .type == \"markdown\" then {markdown: .markdown.content}
            elif .type == \"ask\"      then .ask | {ask: {content, sentAt, who: (if .anon then {anon} else .askingProject | $get_project end) }}
            else .attachment | {img: {altText, fileURL}}
            end
        ),
        poster: .postingProject | $get_project,
        filename, publishedAt, cws, tags
    "
    echo "{ $get_one, shareTree: [.shareTree[] | { $get_one }] }"
}

render() {
    render_one='.rendered = (.content | join("\n\n")) |
        .tags = (.tags | map("#" + .) | join(", ")) |
        .date = (.publishedAt | sub("\\.[0-9]{3}Z";"Z") | fromdate | strftime("%c UTC")) |
        "**\(.poster.displayName) | @\(.poster.handle)** said at \(.date):
```quote
\(.rendered)
```
\(.tags)"'
    echo "(.shareTree | map($render_one)"' | join("\n\n"))'" + ($render_one)"
}

if ! [ $# = 1 ]; then
    die "usage: $0 <username>"
fi

username=$1
page=0

mkdir -p raw parsed rendered img
while true; do
    html=raw/$page.html
    parsed=parsed/$page.json
    rendered=rendered/$page.md
    if ! [ -e $html ]; then
        echo "fetch page $page of posts"
        curl -s "https://cohost.org/$username?page=$page" > $html
    fi
    if [ "$(posts $html | jq length | tr -d '\r')" -eq 0 ]; then
        # no posts left
        break
    fi
    echo "parsing and rendering page $page"
    posts $html | jq "map($(extract))" > $parsed
    # jq < $parsed ".[] | $(render)" -r > $rendered
    python3 ./render.py < $parsed
    page=$((page+1))
done
