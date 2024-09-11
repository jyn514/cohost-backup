# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

param (
	[Parameter(Mandatory)]
	[string]$username
)
	#[string]$sid = $(Get-TokenMaybe)

$ErrorActionPreference = "Stop"

function Test-Application($cmd) {
    return (Get-Command $cmd -ErrorAction SilentlyContinue -CommandType Application | Measure-Object).Count -gt 0
}

function Install-HtmlParser() {
	# Install the PSParseHTML module on demand
	If (-not (Get-Module -ErrorAction Ignore -ListAvailable PSParseHTML)) {
		Write-Output "Installing PSParseHTML module (https://github.com/EvotecIT/PSParseHTML) for the current user..."
		Install-Module -Scope CurrentUser PSParseHTML
	}
}

function Get-Posts($file) {
	# https://stackoverflow.com/a/77447338
	Install-HtmlParser
	write-host $file
	$contents = Get-Content -Raw $file
	#write-host $contents
	$dom = ConvertFrom-Html -Engine AngleSharp -Content $contents
	#write-host $dom
	$json = ConvertFrom-Json ($dom.QuerySelectorAll('script#trpc-dehydrated-state').TextContent)
	write-host $json
	return $json.queries | %{$_.state.data.posts} | Where-Object { $_ -ne $null }
}

function Get-TokenMaybe() {
	$sid = Read-Host -MaskInput "cohost posts are public, but likes are not. to download your liked posts, this script needs to log in as you.
to get your access token, do the following things:
1. open https://cohost.org/ while logged in.
2. open the devtools network tab. if you are on firefox, press ctrl+shift+e. if you are on chrome, press ctrl+shift+i, then click on the 'Network' tab.
3. on the left panel, click on any request which sends a session cookie to cohost.org ('login.loggedIn,projects.listEditedProjects' is often near the top, that's fine to use).
4. on the right panel, click on 'Filter Headers', then type 'Cookie'.
5. under 'Request Headers', you should see a string starting with 'Cookie: connect.sid='. right click it and hit 'copy value'.
6. paste that string here.
if for any reason you don't want this script to log in as you, or you just think that sounds hard and annoying, press Enter now to skip downloading likes.

session cookie (or leave blank to skip downloading liked posts): "
	if (! $sid) {
		Write-Host "no token supplied; skipping liked posts"
		return $null
	}
	(($sid -replace '.*connect.sid=([^ ;]*).*', '$1') -split '\n')[-1]
}

# cohost posts contain 0 or more posts in a chain named "shareTree"; more than 0 indicates this is a quote-post/repost.
# note that cohost does not really distinguish a repost from a quote post without text
function Get-ChainContent($chain) {
	function Get-Project($project) {
		@{id=$project.projectId; handle=$project.handle; displayName=$project.displayName}
	}
	function Get-Post($post) {		
		$content = $post.blocks | %{ switch($_.type) {
			'markdown' { @{markdown=$_.markdown.content} }
			'ask' {
				$ask = $_.ask
				$who = if ($ask.anon) { $ask.anon } else { Get-Project $ask.askingProject }
				@{ask=@{content=$ask.content; sentAt=$ask.sentAt; who=$who}}
			}
			default {
				$attachment = $_.attachment
				@{img=@{altText=$attachment.altText, $attachment.fileURL}}
			}
		} }
		@{content=$content; poster=Get-Project $post.postringProject;
		  filename=$post.filename; publishedAt=$post.publishedAt;
		  cws=$post.cws; tags=$post.tags}
	}
	$d = Get-Post $chain
	$d.shareTree = $chain.shareTree | %{Get-Post $_}
	return $d
}

#function Format-Time($when) {}

#Set-PSDebug -Trace 1
echo $username
$page = 0
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('posts', 'img')
Push-Location posts
trap { Pop-Location }
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('raw', 'parsed', 'rendered')
while($true) {
	$html = "raw/${page}.html"
	$parsed = "parsed/${page}.json"
	if (! (Test-Path $html)) {
		Write-Output "fetch page $page of posts"
		echo "https://cohost.org/${username}?page=$page"
		curl.exe -s "https://cohost.org/${username}?page=$page" > $html
	}
	echo $html
	$posts = Get-Posts $html
	if (($posts | Measure-Object).Count -eq 0) {
		break  # no posts left
	}
	Write-Output "parsing and rendering likes starting from $page"
	$json = $posts | %{ Get-ChainContent $_ }
	$json | Tee-Object $parsed | python3 ../render.py
	$page += 1
}
