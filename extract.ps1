# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

param (
	[Parameter(Mandatory)]
	[string]$username
)
	#[string]$sid = $(Get-TokenMaybe)

$ErrorActionPreference = "Stop"

function Install-HtmlParser() {
	# Install the PSParseHTML module on demand
	If (-not (Get-Module -ErrorAction Ignore -ListAvailable PSParseHTML)) {
		Write-Output "Installing PSParseHTML module (https://github.com/EvotecIT/PSParseHTML) for the current user..."
		Install-Module -Scope CurrentUser PSParseHTML
	}
}

function Get-Posts($file) {
	Install-HtmlParser
	$contents = Get-Content -Raw $file
	$dom = ConvertFrom-Html -Engine AngleSharp -Content $contents
	$json = ConvertFrom-Json ($dom.QuerySelectorAll('script#trpc-dehydrated-state').TextContent)
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
		$content = $post.blocks | %{ $block = $_; switch($block.type) {
			'markdown' { @{markdown=$block.markdown.content} }
			'ask' {
				$ask = $block.ask
				$who = if ($ask.anon) { @{anon=$ask.anon} } else { Get-Project $ask.askingProject }
				@{ask=@{content=$ask.content; sentAt=$ask.sentAt; who=$who}}
			}
			default {
				$attachment = $block.attachment
				@{img=@{altText=$attachment.altText, $attachment.fileURL}}
			}
		} };
		@{content=$content ?? @(); poster=Get-Project $post.postingProject;
		  filename=$post.filename; publishedAt=$post.publishedAt;
		  cws=$post.cws; tags=$post.tags}
	}
	$d = Get-Post $chain
	$d.shareTree = ($chain.shareTree | %{Get-Post $_}) ?? @()
	return $d
}

function Format-Time($when) {
	# TODO: show the abbreviated time zone too
	$when.toLocalTime().toString("yyyy-MM-dd HH:mm:ss")
}

function Format-WhoWhen($who, $when, $how) {
	"**$($who.displayName) | $($who.handle)** ${how} at $(Format-Time $when)"
}

function Format-Post($post){
	$rendered = $post.content | %{
		$keys = $_.keys
		if ("markdown" -in $keys) {
			$_.markdown
		} elseif ("ask" -in $keys) {
			$ask = $_.ask
			$content, $sent, $who = $ask.content, $ask.sentAt, $ask.who
			$who_when = if ($who.anon) {
				"anon asked at $(Format-Time $sent)"
			} else {
				Format-WhoWhen $who $sent "asked"
			}
			'${who_when}:

```quote
' + $content + '
```'
		} else {
			$alt, $url = $_.img.altText ?? "", $_.img.fileUrl
			$url = [uri]$url
			$hash = $url.segments[-2].TrimEnd("/")
			$ext = [System.IO.Path]::GetExtension($url.segments[-1])
			# this is a little absurd :( https://stackoverflow.com/a/73391369
			$dst = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("../img/${hash}$ext")
			if (! (Test-Path $dst) || (Get-Item $dst).length -eq 0) {
				write-host $url
				$global:imgs += ("-o", $dst, $url.AbsoluteUri)
			}
			# markdown doesn't allow newlines in image alt text
            # TODO: figure out how to actually keep these: https://tech.lgbt/@jyn/112117398042554191
            $alt = $alt -replace "`n", ""
			"![$alt](../$dst)"
		}
	} | Join-String -Separator "`n`n"
	$tags = $post.tags | %{"#$_"} | Join-String -Separator ", "
	$who_when = Format-WhoWhen $post.poster $post.publishedAt "said"
	"${who_when}:`n`n$rendered`n`n$tags"
}

$page = 0
$global:imgs = @()
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('posts', 'img')
Push-Location posts
trap { Pop-Location }
New-Item -ItemType Directory -ErrorAction SilentlyContinue @('raw', 'parsed', 'rendered')
while($true) {
	$html = "raw/${page}.html"
	$parsed = "parsed/${page}.json"
	if (! (Test-Path $html) -or (Get-Item $html).length -eq 0) {
		Write-Output "fetch page $page of posts"
		echo "https://cohost.org/${username}?page=$page"
		curl.exe -s "https://cohost.org/${username}?page=$page" > $html
	}
	$posts = Get-Posts $html
	if (($posts | Measure-Object).Count -eq 0) {
		break  # no posts left
	}
	Write-Output "parsing and rendering posts starting from $page"
	$ir = $posts | %{ Get-ChainContent $_ }
	#$ir | ConvertTo-Json -Depth 100 > $parsed
	$ir | %{
		$rendered = ($_.shareTree | %{Format-Post $_}) + (Format-Post $_)
		$rendered | Join-String -Separator "`n`n" > "rendered/$($_.filename).md"
	}
	$page += 1
}

if ($global:imgs) {
	Write-Host "Downloading $($global:imgs.length) images"
	curl.exe --parallel $global:imgs
}
