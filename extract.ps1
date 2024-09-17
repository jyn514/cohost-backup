#!/usr/bin/env pwsh

param (
	[Parameter(Mandatory)]
	[string]$username
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

# Optional chaining, like `?.` in TypeScript
function Select-Property() {
	param(
		[Parameter(ValueFromPipeline)]
		$obj,
		[Parameter(Position, Mandatory)]
		$prop
	)
    if ($obj -eq $null) { return $null }
	($obj | Select-Object $prop).$prop
}

# COALESCE
function Skip-Null() {
	param(
		[Parameter(ValueFromPipeline)]
		$obj,
		[Parameter(Position, Mandatory)]
		$default
	)
	if ($obj -eq $null) { $default } else { $obj }
}

Set-Alias '?.' Select-Property
Set-Alias '??' Skip-Null
if (Test-Path Alias:curl) { Remove-Item Alias:curl }

# Install the PSParseHTML module on demand
function Install-HtmlParser() {
	# Avoid a prompt on base windows
	if (-not (Get-PackageProvider -ListAvailable | Where-Object Name -eq NuGet)) {
		Install-PackageProvider -Scope CurrentUser -Force -name NuGet
	}
	if (-not (Get-Module -ErrorAction Ignore -ListAvailable PSParseHTML)) {
		Install-Module -Scope CurrentUser -Force PSParseHTML
	}
}

function download() {
    # powershell silently strips unknown dash args????
	$curlArgs = $MyInvocation.UnboundArguments
	curl --retry 3 --fail $curlArgs
}

function Get-Posts($file) {
	Install-HtmlParser
	$contents = Get-Content -Raw $file
	$dom = ConvertFrom-Html -Engine AngleSharp -Content $contents
	$json = ConvertFrom-Json ($dom.QuerySelectorAll('script#trpc-dehydrated-state').TextContent)
	return $json.queries | %{$_.state | ?. data | ?. posts} | Where-Object { $_ -ne $null }
}

function Get-Likes($file) {
	Install-HtmlParser
	$contents = Get-Content -Raw $file
	$dom = ConvertFrom-Html -Engine AngleSharp -Content $contents
	$json = ConvertFrom-Json ($dom.QuerySelectorAll('script#__COHOST_LOADER_STATE__').TextContent)
	return $json.'liked-posts-feed'.posts | Where-Object { $_ -ne $null }
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

session cookie (or leave blank to skip downloading liked posts)"
	if (! $sid) {
		Write-Host "no token supplied; skipping liked posts"
		return $null
	} elseif ($sid.toLower() -in @('set-cookie', 'cookie')) {
		Write-Error "you copied multiple lines out of devtools; this script needs you to paste exactly one line (in firefox you can right click and use 'Copy Value')"
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
		$content = $post.blocks | %{ $block = $_; switch($block.type) {
			'markdown' { @{markdown=$block.markdown.content} }
			'ask' {
				$ask = $block.ask
				$who = if ($ask | ?. anon) { @{anon=$ask.anon} } else { Get-Project $ask.askingProject }
				@{ask=@{content=$ask.content; sentAt=$ask.sentAt; who=$who}}
			}
			'attachment' {
				$attachment = $block.attachment
				@{img=@{altText=$attachment | ?. altText; fileUrl=$attachment.fileURL}}
			}
			default {
				Write-Error "unknown content type $($block.type)"
			}
		} };
		@{content=@($content); poster=Get-Project $post.postingProject;
		  filename=$post.filename; publishedAt=$post.publishedAt;
		  cws=$post.cws; tags=$post.tags}
	}
	$d = Get-Post $chain
	$d.shareTree = @($chain.shareTree | %{Get-Post $_})
	return $d
}

function Format-Time($when) {
	# TODO: show the abbreviated time zone too
	([datetime]$when).toLocalTime().toString("yyyy-MM-dd HH:mm:ss")
}

function Format-WhoWhen($who, $when, $how) {
	"**$($who.displayName) | $($who.handle)** ${how} at $(Format-Time $when)"
}

function Format-Post($post) {
	$rendered = $post.content | %{
		$keys = $_.keys
		if ("markdown" -in $keys) {
			$_.markdown
		} elseif ("ask" -in $keys) {
			$ask = $_.ask
			$content, $sent, $who = $ask.content, $ask.sentAt, $ask.who
			$who_when = if ($who | ?. anon) {
				"anon asked at $(Format-Time $sent)"
			} else {
				Format-WhoWhen $who $sent "asked"
			}
			'${who_when}:

```quote
' + $content + '
```'
		} else {
			$alt, $url = ($_.img.altText | ?? ""), [uri]$_.img.fileUrl
			$hash = $url.segments[-2].TrimEnd("/")
			$ext = [System.IO.Path]::GetExtension($url.segments[-1])
			# this is a little absurd :( https://stackoverflow.com/a/73391369
			$dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("../img/${hash}$ext")
			if (! (Test-Path $dst) -or (Get-Item $dst).length -eq 0) {
				# note: curl tries to interpret backslashes in configs :(
				$global:imgs += 'output="' + ($dst -replace "\\", "\\") + '"'
				# for reasons i don't understand, powershell puts this on the same line when passed to curl if we use $imgs += (output, url), so it has to be a separate statement
				$global:imgs += 'url='+$url.AbsoluteUri
			}
			# markdown doesn't allow newlines in image alt text
            # TODO: figure out how to actually keep these: https://tech.lgbt/@jyn/112117398042554191
            $alt = $alt -replace "`n", ""
			"![$alt](file:///$dst)"
		}
	}
	$tags = $post.tags | %{"#$_"}
	$who_when = Format-WhoWhen $post.poster $post.publishedAt "said"
	"${who_when}:`n`n" + ($rendered -join "`n`n") + "`n`n" + ($tags -join ", ")
}

function Write-Chain($ir) {
	$rendered = ($ir.shareTree | %{Format-Post $_}) + (Format-Post $ir)
	$rendered -join "`n`n" > "rendered/$($_.filename).md"
}

function Get-AllLikes($sid) {
	# download likes
	Push-Location ../likes
	trap { Pop-Location }
	New-Item -ItemType Directory -ErrorAction SilentlyContinue @('raw', 'parsed', 'rendered') >$null
	$page = 0
	$liked = 0
	while($true) {
		$html = "raw/${page}.html"
		$parsed = "parsed/${page}.json"
		if (! (Test-Path $html) -or (Get-Item $html).length -eq 0) {
			Write-Output "fetching page $page of likes"
			download --no-progress-meter "https://cohost.org/rc/liked-posts?skipPosts=$liked" --cookie "connect.sid=$sid" -o $html
			if ((Get-Item $html | Measure-Object -Line).lines -eq 1 -and (Get-Content $html) -like '*/rc/login*') {
				Remove-Item $html
				Write-Error "cohost thinks you're not logged in (are you sure you pasted the right token?)"
			}
		}
		$posts = Get-Likes $html
		$num_likes = ($posts | Measure-Object).Count
		if ($num_likes -eq 0) {
			break  # no posts left
		}
		Write-Output "parsing and rendering liked posts starting from page $page"
		$ir = $posts | %{ Get-ChainContent $_ }
		$ir | ConvertTo-Json -Depth 100 > $parsed
		$ir | %{ Write-Chain $_ }
		$page += 1
		$liked += $num_likes
	}
}

$sid = Get-TokenMaybe
$global:imgs = @()

# download posts
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('posts', 'likes', 'img') >$null
Push-Location posts
trap { Pop-Location }
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('raw', 'parsed', 'rendered') >$null
$page = 0
while($true) {
	$html = "raw/${page}.html"
	$parsed = "parsed/${page}.json"
	if (! (Test-Path $html) -or (Get-Item $html).length -eq 0) {
		Write-Output "fetch page $page of posts"
		download --no-progress-meter "https://cohost.org/${username}?page=$page" -o $html
	}
	$posts = Get-Posts $html
	if (($posts | Measure-Object).Count -eq 0) {
		break  # no posts left
	}
	Write-Output "parsing and rendering posts starting from page $page"
	$ir = $posts | %{ Get-ChainContent $_ }
	$ir | ConvertTo-Json -Depth 100 > $parsed
	$ir | %{ Write-Chain $_ }
	$page += 1
}


if ($sid) {
	Get-AllLikes $sid
} else {
	Write-Warning "no access token provided; can't download liked posts"
}

if ($global:imgs) {
	Write-Host "Downloading $($global:imgs.length) images"
	$global:imgs | download -K -
}
