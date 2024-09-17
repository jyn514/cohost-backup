# cohost backup

## what does it look like

![a screenshot of https://cohost.org/jyn/post/5004479-oh-my-god-i-just-dis rendered to html.](./example.png)

## how do i use it

### what do i need to install

you will need [Powershell][install pwsh] installed.
Windows comes pre-installed with Powershell 5; that's fine.
most linux distros package powershell for you, don't give me that look.

### how do i download it

if you are familiar with git, you can git clone this repo.
if you are not familiar with git, the powershell script is standalone and needs no other files. you can download it directly from [here][github-browser] (click "Download raw file" near the right toolbar).

![image](https://github.com/user-attachments/assets/ca0e6d0c-08a3-4445-be11-2ca54ce227e3)

(i can't give a direct link unfortunately because Windows tries to save it as a .txt file 😔)

[github-browser]: https://github.com/jyn514/cohost-backup/blob/main/extract.ps1

### how do i run it

the entrypoint is the powershell script; pass it your cohost handle
```
./extract.ps1 jyn
```

#### wait what does that mean where do i type that

if you don't know what the `./` symbols mean, you can also right click the script in Windows Explorer and click 'Run with Powershell'; it will prompt you for your username.

if that does nothing and exits, you likely have powershell scripts blocked (this is the default).
do the following things:
1. right click on the folder and click 'Open in Terminal'
2. run `powershell.exe -noprofile -executionpolicy bypass -file .\extract.ps1`

### what does it do

the script will create this directory structure:
```
PS C:\Users\jyn\src\cohost-backup> tree
Folder PATH listing
C:.
├───img
├───likes
│   ├───parsed
│   ├───raw
│   └───rendered
└───posts
    ├───parsed
    ├───raw
    └───rendered
```
the files you care about are in `rendered`. there will be a lot of them, especially in `likes`.

the first run will take longer because it downloads a bunch of images. after that it just has to ensure the rendered JSON and .md files are up to date, so it should be faster.

### how can i view the files it creates

you can use any markdown renderer; i like [obsidian](https://obsidian.md/).
you also have the option to use the `Show-Markdown` commandlet built into powershell.

### are you really sure i have to use powershell

there is a previous version in bash but i consider it unmaintained and will probably delete it eventually. run it with `./extract.sh username`.

## i don't like the markdown it generates

feel free to change it lol, look around `Format-Post`

i am considering consolidating the posts into one giant amalgamation, but haven't thought of an appropriate separator between posts yet.

## this is really messy

if you want to port it to cohost.py, be my guest. i'm not gonna bother.

[install pwsh]: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.4
