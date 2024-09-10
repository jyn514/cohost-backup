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

likes() {
    html=$1
    pup 'script#__COHOST_LOADER_STATE__' 'text{}' < $html \
        | jq '."liked-posts-feed" | .posts'
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

get_token_maybe() {
    printf %s "cohost posts are public, but likes are not. to download your liked posts, this script needs to log in as you.
to get your access token, do the following things:
1. open https://cohost.org/ while logged in.
2. open the devtools network tab. if you are on firefox, press ctrl+shift+e. if you are on chrome, press ctrl+shift+i, then click on the 'Network' tab.
3. on the left panel, click on any request which sends a session cookie to cohost.org ('login.loggedIn,projects.listEditedProjects' is often near the top, that's fine to use).
4. on the right panel, click on 'Filter Headers', then type 'Cookie'.
5. under 'Request Headers', you should see a string starting with 'Cookie: connect.sid='. right click it and hit 'copy value'.
6. paste that string here.
if for any reason you don't want this script to log in as you, or you just think that sounds hard and annoying, press Enter now to skip downloading likes.

session cookie (or leave blank to skip downloading liked posts): ">&2
    read -s sid
    if ! [ "$sid" ]; then echo "no token supplied; skipping liked posts">&2; fi
    # be lenient about how much of the token is copied
    sid=$(printf %s "$sid" | tr -d '\n' | sed -E 's/connect.sid=([^ ;]*)/\1/')
}

if ! [ $# = 1 ]; then
    die "usage: $0 <username>"
fi

get_token_maybe

username=$1
page=0

mkdir -p posts img
pushd posts>/dev/null
mkdir -p raw parsed rendered
while true; do
    html=raw/$page.html
    parsed=parsed/$page.json
    if ! [ -e $html ]; then
        echo "fetch page $page of posts"
        curl -s "https://cohost.org/$username?page=$page" > $html
    fi
    if [ "$(posts $html | jq length | tr -d '\r')" -eq 0 ]; then
        # no posts left
        break
    fi
    echo "parsing and rendering likes starting from $page"
    posts $html | jq "map($(extract))" > $parsed
    python3 ../render.py < $parsed
    page=$((page+1))
done
popd>/dev/null

if ! [ "$sid" ]; then
    echo "no access token provided; can't download liked posts">&2
    exit
fi

mkdir -p likes
pushd likes>/dev/null
mkdir -p raw parsed rendered
liked_posts=0
page=0
while true; do
    html=raw/$page.html
    parsed=parsed/$page.json
    if ! [ -e $html ]; then
        echo "fetch page $page of likes"
        curl -s "https://cohost.org/rc/liked-posts?skipPosts=$liked_posts" --cookie "connect.sid=$sid" > $html
    fi
    num_likes=$(likes $html | jq length | tr -d '\r') 
    if [ "$num_likes" -eq 0 ]; then
        # no posts left
        break
    fi
    echo "parsing and rendering likes starting from $liked_posts"
    likes $html | jq "map($(extract))" > $parsed
    python3 ../render.py < $parsed
    liked_posts=$((liked_posts+num_likes))
    page=$((page+1))
done
popd>/dev/null
