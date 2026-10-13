# pwsh serve.ps1 a 1234

$types = @{
    'css' = 'text/css';
    'html' = 'text/html';
    'ico' = 'image/x-icon';
    'js' = 'application/javascript'
}

function serve($folder, $port) {
    $folder = $folder ?? 'a'
    $port = $port ?? 1234
    $index = '/x.html'
    if ($folder.EndsWith('.html')) {
        if (($i = $folder.LastIndexOf('/')) -ne -1) {
            $index = $folder.Substring($i)
            $folder = $folder.Substring(0, $i)
        }
    }
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add('http://localhost:' + $port + '/')
    $listener.Start()
    Write-Host('localhost:' + $port)
    try {
        while ($listener.IsListening) {
            $task = $listener.GetContextAsync()
            while (-not $task.AsyncWaitHandle.WaitOne(100)) {}
            $context = $task.GetAwaiter().GetResult()
            $file = $context.Request.Url.LocalPath
            if ($file[0] -ne '/' -or $file.IndexOf('..') -ne -1) {
                continue
            }
            $file = $file.Replace('%20', ' ')
            $type = $file.Substring($file.LastIndexOf('.') + 1)
            if ($types.ContainsKey($type)) {
                $type = $types[$type]
            } else {
                $file = $index
                $type = 'text/html'
            }
            $file = $folder + $file
            if (Test-Path -Path $file) {
                $content = [System.IO.File]::ReadAllBytes($file)
                $response = $context.Response
                $response.ContentType = $type
                $output = $response.OutputStream
                $output.Write($content, 0, $content.Length)
                $output.Close()
            }
        }
    } finally {
        $listener.Stop()
    }
}

serve $args[0] $args[1]