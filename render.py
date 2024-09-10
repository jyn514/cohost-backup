#!/usr/bin/env python3
import json, sys
from os import path
from datetime import datetime
from urllib import request

def render_time(when):
    return datetime.strptime(when, "%Y-%m-%dT%H:%M:%S.%f%z").astimezone().strftime("%F %T %Z")

def render_who_when(who, when, how):
    return f"""**{who["displayName"]} | @{who["handle"]}** {how} at {render_time(when)}:"""

# the markdown is vaguely based around Zulip's, but massaged to look more like cohost's html formatting
def render(post):
    rendered = []
    for block in post["content"]:
        if "markdown" in block:
            rendered.append(block["markdown"])
        elif "ask" in block:
            ask = block["ask"]
            content, sent, who = ask["content"], ask["sentAt"], ask["who"]
            if who.get("anon"):
                who_when = f"anon asked at {render_time(sent)}"
            else:
                who_when = render_who_when(ask["who"], sent, "asked")
            rendered.append(f"""{who_when}:
            ```quote
            {content}
            ```
            """)
        else:
            img = block["img"]
            alt, url = img["altText"], img["fileURL"]
            alt = alt or ""
            basename = url.split("/")[-2] + path.splitext(url.split("/")[-1])[1]
            dst = f"../img/{basename}"
            if not path.exists(dst):
                with request.urlopen(url) as download:
                    img = download.read()
                with open(dst, 'wb') as f:
                    f.write(img)
            dst = "../" + dst
            # markdown doesn't allow newlines in image alt text
            # TODO: figure out how to actually keep these: https://tech.lgbt/@jyn/112117398042554191
            alt = alt.replace("\n", " ")
            rendered.append(f"![{alt}]({dst})")
    rendered = "\n\n".join(rendered)
    tags = ", ".join("#" + tag for tag in post["tags"])
    who_when = render_who_when(post["poster"], post["publishedAt"], "said")
    return f"""{who_when}

{rendered}

{tags}"""

for post in json.load(sys.stdin):
    rendered = "\n\n".join([render(share) for share in post["shareTree"]] + [render(post)])
    with open(f"""rendered/{post["filename"]}.md""", "w") as f:
        f.write(rendered)
