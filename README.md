# cohost backup

## what does it look like

![a screenshot of https://cohost.org/jyn/post/5004479-oh-my-god-i-just-dis rendered to html.](./example.png)

## how do i use it

you will need [Powershell 7][install pwsh] installed.
note that Windows comes pre-installed with Powershell 5 which is *not* the same and will not work. make sure to install pwsh 7 with `winget install --id Microsoft.PowerShell --source winget`.
most linux distros package powershell for you, don't give me that look.

the entrypoint is the powershell script; pass it your cohost handle
```
./extract.ps1 jyn
```

the first run will take longer because it downloads a bunch of images. after that it just has to check the rendered JSON and .md files are up to date, so it should be faster.

note that the image links are relative to the *generated* markdown files, you'll need to be in the `rendered` directory for the links to work right.

### are you really sure i have to use powershell

there is a previous version in bash but i consider it unmaintained and will probably delete it eventually. run it with `./extract.sh username`.

## i don't like the markdown it generates

feel free to change it lol, look around `Format-Post`

i am considering consolidating the posts into one giant amalgamation, but haven't thought of an appropriate separator between posts yet.

## this is really messy

if you want to port it to cohost.py, be my guest. i'm not gonna bother.

[install pwsh]: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.4
