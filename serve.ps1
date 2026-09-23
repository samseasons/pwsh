# ./serve.ps1 a 1234

$types = @{
    'css' = 'text/css';
    'html' = 'text/html';
    'ico' = 'image/x-icon';
    'js' = 'application/javascript'
}

function serve($folder, $port) {
    $folder = $folder ?? 'a'
    $port = $port ?? 1234
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add('http://localhost:' + $port + '/')
    $listener.Start()
    Write-Host('localhost:' + $port)
    try {
        while ($listener.IsListening) {
            $task = $listener.GetContextAsync()
            while (!$task.AsyncWaitHandle.WaitOne(100)) {}
            $context = $task.GetAwaiter().GetResult()
            $file = $context.Request.Url.LocalPath.Replace('%20', ' ')
            if ($file[0] -ne '/' -or $file -eq '/') {
                $file = '/x.html'
                $type = 'text/html'
            } else {
                $type = $types[$file.Substring($file.LastIndexOf('.') + 1)]
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