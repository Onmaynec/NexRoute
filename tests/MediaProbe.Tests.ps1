Describe 'NexRoute 0.6.0 media and throughput probes' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-media.ps1')
        $script:server=$null
        $script:fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-media-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixture -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fixture 'media') -Force | Out-Null
        $large=New-Object byte[] (3*1024*1024)
        for ($i=0;$i -lt $large.Length;$i++) { $large[$i]=[byte]($i % 251) }
        [IO.File]::WriteAllBytes((Join-Path $script:fixture 'download.bin'),$large)
        $segment=New-Object byte[] 65536
        for ($i=0;$i -lt $segment.Length;$i++) { $segment[$i]=[byte](255-($i % 251)) }
        [IO.File]::WriteAllBytes((Join-Path $script:fixture 'media/segment0.ts'),$segment)
        [IO.File]::WriteAllText((Join-Path $script:fixture 'master.m3u8'),"#EXTM3U`n#EXT-X-STREAM-INF:BANDWIDTH=1000000`nmedia/index.m3u8`n",[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $script:fixture 'media/index.m3u8'),"#EXTM3U`n#EXT-X-TARGETDURATION:4`n#EXTINF:4.0,`nsegment0.ts`n#EXT-X-ENDLIST`n",[Text.UTF8Encoding]::new($false))
        $script:port=Get-Random -Minimum 22000 -Maximum 42000
        $python=(Get-Command python3 -ErrorAction SilentlyContinue)
        if (-not $python) { $python=Get-Command python -ErrorAction Stop }
        $script:server=Start-Process -FilePath $python.Source -ArgumentList @('-m','http.server',[string]$script:port,'--bind','127.0.0.1','--directory',$script:fixture) -PassThru
        $ready=$false
        for ($attempt=0;$attempt -lt 30;$attempt++) {
            try {
                $response=Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/master.m3u8" -f $script:port) -UseBasicParsing -TimeoutSec 1
                if ($response.StatusCode -eq 200) { $ready=$true; break }
            } catch { Start-Sleep -Milliseconds 100 }
        }
        if (-not $ready) { throw 'Local media fixture server did not start.' }
    }

    AfterAll {
        if ($null -ne $script:server -and -not $script:server.HasExited) { Stop-Process -Id $script:server.Id -Force -ErrorAction SilentlyContinue }
        if ($script:fixture) { Remove-Item -LiteralPath $script:fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'streams a multi-megabyte payload and calculates throughput from received bytes' {
        $result=Measure-NrStreamingDownload -Uri ([Uri]("http://127.0.0.1:{0}/download.bin" -f $script:port)) -TargetBytes (2*1024*1024) -TimeoutSeconds 10
        $result.ok | Should -BeTrue
        $result.receivedBytes | Should -Be (2*1024*1024)
        $result.megabitsPerSecond | Should -BeGreaterThan 0
        $result.statusCode | Should -Be 200
    }

    It 'loads a master playlist variant and a real media segment' {
        $result=Test-NrHlsPlaybackReadiness -ManifestUri ([Uri]("http://127.0.0.1:{0}/master.m3u8" -f $script:port)) -MinimumSegmentBytes 60000
        $result.ok | Should -BeTrue
        $result.usedMasterPlaylist | Should -BeTrue
        $result.segmentBytes | Should -Be 65536
        $result.mediaPlaylistUri | Should -Match '/media/index\.m3u8$'
        $result.segmentUri | Should -Match '/media/segment0\.ts$'
    }

    It 'rejects undersized HLS segments instead of reporting a false success' {
        $result=Test-NrHlsPlaybackReadiness -ManifestUri ([Uri]("http://127.0.0.1:{0}/master.m3u8" -f $script:port)) -MinimumSegmentBytes 70000
        $result.ok | Should -BeFalse
        $result.segmentBytes | Should -Be 65536
    }
}
