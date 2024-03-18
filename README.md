# cohost backup

## what does it look like

![a screenshot of https://cohost.org/jyn/post/5004479-oh-my-god-i-just-dis rendered to html.](./example.png)

## how do i use it

ok jsyk i only tested this on WSL lol, it will *probably* work on linux as long as you remove the `.exe` suffixes.

you will need curl, python3, [jq], and [pup] installed.

the entrypoint is the shell script; pass it your cohost handle
```
./extract.sh jyn
```

the first run will take longer because it downloads a bunch of images. after that it just has to check the rendered JSON and .md files are up to date, so it should be faster.

note that the image links are relative to the *generated* markdown files, you'll need to be in the `rendered` directory for the links to work right.

## i don't like the markdown it generates

feel free to change it lol, look around `render.py`

i am considering consolidating the posts into one giant amalgamation, but haven't thought of an appropriate separator between posts yet.

## this is really messy

if you want to port it to cohost.py, be my guest. i'm not gonna bother.

[jq]: https://jqlang.github.io/jq/
[pup]: https://github.com/ericchiang/pup
