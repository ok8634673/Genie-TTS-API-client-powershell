<#
DeepSeek-TTSClient.ps1
WPF GUI for TTS API (load/unload/set_reference_audio/tts/stop/clear_reference_audio_cache)
保存为 DeepSeek-TTSClient.ps1 并运行（会自动在 STA 下重启自己，如果当前不是 STA）
#>

# 如果当前线程不是 STA，则用 -STA 重新启动脚本并退出当前进程
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host "当前不是 STA 线程，重新启动..."
    
    # 获取 PowerShell 可执行文件路径
    $powershellPath = (Get-Command "powershell.exe" -ErrorAction SilentlyContinue).Source
    if (-not $powershellPath) {
        $powershellPath = "powershell.exe"
    }
    
    # 构建参数
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = "-STA -ExecutionPolicy Bypass -File `"$scriptPath`""
    
    Write-Host "启动命令: $powershellPath $arguments"
    
    try {
        Start-Process -FilePath $powershellPath -ArgumentList $arguments -Wait
    } catch {
        Write-Host "启动失败: $($_.Exception.Message)"
        # 尝试在当前进程继续（可能会失败）
        Write-Host "尝试在当前进程继续..."
    }
    exit
}

Write-Host "在 STA 线程中运行..."

# Load assemblies
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Write-Host "WPF 程序集加载成功"
} catch {
    Write-Host "WPF 程序集加载失败: $($_.Exception.Message)"
    exit
}

# Load System.Windows.Forms for FolderBrowserDialog fallback & SoundPlayer
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Host "Windows Forms 程序集加载成功"
} catch {
    Write-Host "Windows Forms 程序集加载失败: $($_.Exception.Message)"
}

# ----------------- 配置加载/保存 -----------------
$Script:ConfigFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "config.json"
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Load-Config {
    if (Test-Path $Script:ConfigFile) {
        try {
            $Script:Config = Get-Content $Script:ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop
            Write-Host "配置加载成功"
        } catch {
            Write-Host "配置加载失败: $($_.Exception.Message)"
            $Script:Config = @{}
        }
    } else {
        Write-Host "配置文件不存在，创建默认配置"
        $Script:Config = @{}
    }
    if (-not $Script:Config.base_url) { 
        $Script:Config.base_url = "http://127.0.0.1:8000" 
        Write-Host "设置默认 API 地址: $($Script:Config.base_url)"
    }
    if (-not $Script:Config.audio_cache_dir) {
        $Script:Config.audio_cache_dir = Join-Path $Script:ScriptDir "TTSAudioCache"
        Write-Host "设置默认音频缓存目录: $($Script:Config.audio_cache_dir)"
    }
}
function Save-Config {
    try {
        $Script:Config | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:ConfigFile -Encoding UTF8
        Write-Host "配置保存成功"
    } catch {
        Write-Host "配置保存失败: $($_.Exception.Message)"
    }
}
Load-Config

# ----------------- XAML UI -----------------
Write-Host "加载 XAML..."
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="TTS API 客户端 (WPF)" 
    Height="700" 
    Width="980" 
    WindowStartupLocation="CenterScreen"
    Name="MainWindow">
    
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Margin" Value="4"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Padding" Value="6,2"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Margin" Value="4"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
    </Window.Resources>
    
    <DockPanel>
        <StatusBar DockPanel.Dock="Bottom" Name="StatusBar">
            <StatusBarItem>
                <TextBlock Name="StatusText">就绪</TextBlock>
            </StatusBarItem>
        </StatusBar>

        <Grid Margin="8">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Text="TTS API 客户端 (WPF)" FontWeight="Bold"/>

            <TabControl Grid.Row="1" Name="MainTabControl">
                <!-- Character Tab -->
                <TabItem Header="角色管理" Name="CharacterTab">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="10">
                            <GroupBox Header="加载角色" Margin="4">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="120"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Grid.Column="0">角色名称:</TextBlock>
                                        <TextBox Grid.Row="0" Grid.Column="1" Name="CharacterNameTextBox"/>

                                        <TextBlock Grid.Row="1" Grid.Column="0">模型目录:</TextBlock>
                                        <TextBox Grid.Row="1" Grid.Column="1" Name="ModelDirectoryTextBox"/>
                                        <Button Grid.Row="1" Grid.Column="2" Name="BrowseModelButton">浏览...</Button>
                                    </Grid>
                                    <Button Name="LoadCharacterButton" Width="110" HorizontalAlignment="Right">加载角色</Button>
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Header="卸载角色" Margin="4">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0">角色名称:</TextBlock>
                                    <TextBox Grid.Column="1" Name="UnloadCharacterTextBox"/>
                                    <Button Grid.Column="2" Name="UnloadCharacterButton" Width="90">卸载角色</Button>
                                </Grid>
                            </GroupBox>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <!-- Reference Audio Tab -->
                <TabItem Header="参考音频" Name="ReferenceAudioTab">
                    <StackPanel Margin="10">
                        <GroupBox Header="设置参考音频" Margin="4">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <TextBlock Grid.Row="0" Grid.Column="0">角色名称:</TextBlock>
                                    <TextBox Grid.Row="0" Grid.Column="1" Name="ReferenceCharacterTextBox"/>

                                    <TextBlock Grid.Row="1" Grid.Column="0">音频文件:</TextBlock>
                                    <TextBox Grid.Row="1" Grid.Column="1" Name="AudioFilePathTextBox"/>
                                    <Button Grid.Row="1" Grid.Column="2" Name="BrowseAudioButton">浏览...</Button>

                                    <TextBlock Grid.Row="2" Grid.Column="0" VerticalAlignment="Top" Margin="0,6,0,0">音频文本:</TextBlock>
                                    <TextBox Grid.Row="2" Grid.Column="1" Name="AudioTextTextBox" AcceptsReturn="True" Height="80" TextWrapping="Wrap"/>
                                </Grid>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button Name="SaveReferenceConfigButton" Width="110">保存配置</Button>
                                    <Button Name="SetReferenceAudioButton" Width="140">设置参考音频</Button>
                                </StackPanel>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </TabItem>

                <!-- TTS Tab -->
                <TabItem Header="文本转语音" Name="TTSTab">
                    <StackPanel Margin="10">
                        <GroupBox Header="文本转语音" Margin="4">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <TextBlock Grid.Row="0" Grid.Column="0">角色名称:</TextBlock>
                                    <TextBox Grid.Row="0" Grid.Column="1" Name="TTSCharacterTextBox"/>

                                    <TextBlock Grid.Row="1" Grid.Column="0" VerticalAlignment="Top" Margin="0,6,0,0">要转换的文本:</TextBlock>
                                    <TextBox Grid.Row="1" Grid.Column="1" Name="TTSTextTextBox" AcceptsReturn="True" Height="140" TextWrapping="Wrap"/>

                                    <CheckBox Grid.Row="2" Grid.Column="1" Name="SplitSentenceCheckBox" Content="分割句子" IsChecked="True"/>

                                    <StackPanel Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="3" Orientation="Horizontal" VerticalAlignment="Center">
                                        <TextBlock>保存路径:</TextBlock>
                                        <TextBox Name="SavePathTextBox" Width="540"/>
                                        <Button Name="BrowseSavePathButton">浏览...</Button>
                                    </StackPanel>
                                </Grid>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button Name="StopTTSButton" Width="90">停止</Button>
                                    <Button Name="StartTTSButton" Width="140">开始 TTS (保存)</Button>
                                    <Button Name="SpeakTextButton" Width="260">朗读文本</Button>
                                </StackPanel>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </TabItem>

                <!-- Tools Tab -->
                <TabItem Header="工具" Name="ToolsTab">
                    <StackPanel Margin="10">
                        <GroupBox Header="API 配置" Margin="4">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock>API 地址:</TextBlock>
                                <TextBox Name="ApiUrlTextBox" Width="540"/>
                                <Button Name="UpdateApiButton" Width="90">更新</Button>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="音频缓存配置" Margin="4">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock>缓存目录:</TextBlock>
                                    <TextBox Name="AudioCacheDirTextBox" Width="540"/>
                                    <Button Name="BrowseAudioCacheDirButton">浏览...</Button>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button Name="UpdateAudioCacheDirButton" Width="90">更新</Button>
                                    <Button Name="OpenAudioCacheDirButton" Width="140">打开缓存目录</Button>
                                </StackPanel>
                            </StackPanel>
                        </GroupBox>

                        <StackPanel Orientation="Horizontal" Margin="4">
                            <Button Name="ClearCacheButton" Width="220">清除参考音频缓存</Button>
                            <Button Name="TestConnectionButton" Width="120">测试连接</Button>
                        </StackPanel>
                    </StackPanel>
                </TabItem>
            </TabControl>
        </Grid>
    </DockPanel>
</Window>
"@

Write-Host "XAML 加载完成，创建窗口..."

# ----------------- XAML 加载 -----------------
try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Write-Host "窗口创建成功"
} catch {
    Write-Host "XAML加载失败: $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("XAML加载失败: $($_.Exception.Message)", "错误", "OK", "Error")
    exit
}

# 获取控件引用（通过 Name）
Write-Host "获取控件引用..."

# 使用更可靠的方法获取控件
function Find-Control {
    param([string]$ControlName)
    
    $control = $window.FindName($ControlName)
    if ($control -eq $null) {
        Write-Host "警告: 控件 '$ControlName' 未找到"
    } else {
        Write-Host "成功: 控件 '$ControlName' 已找到"
    }
    return $control
}

# 获取所有控件引用
$StatusText = Find-Control "StatusText"
$CharacterNameTextBox = Find-Control "CharacterNameTextBox"
$ModelDirectoryTextBox = Find-Control "ModelDirectoryTextBox"
$BrowseModelButton = Find-Control "BrowseModelButton"
$LoadCharacterButton = Find-Control "LoadCharacterButton"
$UnloadCharacterTextBox = Find-Control "UnloadCharacterTextBox"
$UnloadCharacterButton = Find-Control "UnloadCharacterButton"

$ReferenceCharacterTextBox = Find-Control "ReferenceCharacterTextBox"
$AudioFilePathTextBox = Find-Control "AudioFilePathTextBox"
$BrowseAudioButton = Find-Control "BrowseAudioButton"
$AudioTextTextBox = Find-Control "AudioTextTextBox"
$SaveReferenceConfigButton = Find-Control "SaveReferenceConfigButton"
$SetReferenceAudioButton = Find-Control "SetReferenceAudioButton"

$TTSCharacterTextBox = Find-Control "TTSCharacterTextBox"
$TTSTextTextBox = Find-Control "TTSTextTextBox"
$SplitSentenceCheckBox = Find-Control "SplitSentenceCheckBox"
$SavePathTextBox = Find-Control "SavePathTextBox"
$BrowseSavePathButton = Find-Control "BrowseSavePathButton"
$StopTTSButton = Find-Control "StopTTSButton"
$StartTTSButton = Find-Control "StartTTSButton"
$SpeakTextButton = Find-Control "SpeakTextButton"

$ApiUrlTextBox = Find-Control "ApiUrlTextBox"
$UpdateApiButton = Find-Control "UpdateApiButton"
$AudioCacheDirTextBox = Find-Control "AudioCacheDirTextBox"
$BrowseAudioCacheDirButton = Find-Control "BrowseAudioCacheDirButton"
$UpdateAudioCacheDirButton = Find-Control "UpdateAudioCacheDirButton"
$OpenAudioCacheDirButton = Find-Control "OpenAudioCacheDirButton"
$ClearCacheButton = Find-Control "ClearCacheButton"
$TestConnectionButton = Find-Control "TestConnectionButton"

Write-Host "控件引用获取完成"

# 初始化字段
if ($ApiUrlTextBox -ne $null) {
    $ApiUrlTextBox.Text = $Script:Config.base_url
}
if ($AudioCacheDirTextBox -ne $null) {
    $AudioCacheDirTextBox.Text = $Script:Config.audio_cache_dir
}
if ($Script:Config.recent_character) {
    if ($CharacterNameTextBox -ne $null) { $CharacterNameTextBox.Text = $Script:Config.recent_character }
    if ($UnloadCharacterTextBox -ne $null) { $UnloadCharacterTextBox.Text = $Script:Config.recent_character }
    if ($ReferenceCharacterTextBox -ne $null) { $ReferenceCharacterTextBox.Text = $Script:Config.recent_character }
    if ($TTSCharacterTextBox -ne $null) { $TTSCharacterTextBox.Text = $Script:Config.recent_character }
}
if ($Script:Config.recent_model_dir -and $ModelDirectoryTextBox -ne $null) { $ModelDirectoryTextBox.Text = $Script:Config.recent_model_dir }
if ($Script:Config.recent_audio_path -and $AudioFilePathTextBox -ne $null) { $AudioFilePathTextBox.Text = $Script:Config.recent_audio_path }
if ($Script:Config.recent_audio_text -and $AudioTextTextBox -ne $null) { $AudioTextTextBox.Text = $Script:Config.recent_audio_text }
if ($Script:Config.recent_tts_text -and $TTSTextTextBox -ne $null) { $TTSTextTextBox.Text = $Script:Config.recent_tts_text }
if ($Script:Config.recent_tts_save -and $SavePathTextBox -ne $null) { $SavePathTextBox.Text = $Script:Config.recent_tts_save }

Write-Host "字段初始化完成"

# ----------------- 公用函数 -----------------
function Set-Status([string]$text) {
    # 使用 Dispatcher 调用 UI 线程
    if ($window -ne $null -and $StatusText -ne $null) {
        $window.Dispatcher.Invoke([action]{ $StatusText.Text = $text })
    }
}

function Show-Info([string]$text) {
    if ($window -ne $null) {
        [System.Windows.MessageBox]::Show($window, $text, "提示", "OK") | Out-Null
    } else {
        [System.Windows.MessageBox]::Show($text, "提示", "OK") | Out-Null
    }
}
function Show-Error([string]$text) {
    if ($window -ne $null) {
        [System.Windows.MessageBox]::Show($window, $text, "错误", "OK", "Error") | Out-Null
    } else {
        [System.Windows.MessageBox]::Show($text, "错误", "OK", "Error") | Out-Null
    }
}

# 浏览目录/文件的通用方法
function Browse-Folder([string]$title = "选择文件夹") {
    # 使用 WPF 的 OpenFileDialog
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = $title
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.FileName = "选择文件夹"
    
    $result = $dlg.ShowDialog()
    if ($result -eq $true) {
        return [System.IO.Path]::GetDirectoryName($dlg.FileName)
    }
    return $null
}

function Browse-File([string]$filter = "所有文件 (*.*)|*.*", [string]$title = "选择文件") {
    # 使用 Microsoft.Win32.OpenFileDialog（WPF 原生）
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Filter = $filter
    $ofd.Title = $title
    $res = $ofd.ShowDialog()
    if ($res -eq $true) { return $ofd.FileName } else { return $null }
}

function Browse-SaveFile([string]$filter = "WAV 文件 (*.wav)|*.wav|所有文件 (*.*)|*.*", [string]$title = "保存文件为...") {
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = $filter
    $sfd.Title = $title
    $res = $sfd.ShowDialog()
    if ($res -eq $true) { return $sfd.FileName } else { return $null }
}

# 生成安全的文件名
function Get-SafeFileName([string]$text, [int]$maxLength = 30) {
    # 移除或替换文件名中的非法字符
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeText = $text -replace "[$([regex]::Escape($invalidChars -join ''))]", "_"
    
    # 限制文件名长度
    if ($safeText.Length -gt $maxLength) {
        $safeText = $safeText.Substring(0, $maxLength)
    }
    
    # 如果文本为空或只有空白字符，使用默认名称
    if ([string]::IsNullOrWhiteSpace($safeText)) {
        $safeText = "audio"
    }
    
    return $safeText
}

# 获取音频缓存目录
function Get-AudioCacheDir {
    $cacheDir = $Script:Config.audio_cache_dir
    if (-not (Test-Path $cacheDir)) {
        try {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        } catch {
            # 如果创建失败，回退到临时目录
            $cacheDir = [System.IO.Path]::GetTempPath()
        }
    }
    return $cacheDir
}

# ================= 简化的 API 调用模块 =================
function Invoke-TTSApi {
    param(
        [string]$Endpoint,
        [hashtable]$Body = $null,
        [int]$TimeoutSeconds = 120
    )
    
    $uri = "$($Script:Config.base_url)$Endpoint"
    
    try {
        # 使用 WebClient 确保 UTF-8 编码
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("Content-Type", "application/json; charset=utf-8")
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        
        # 转换为 JSON
        $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
        
        # 发送请求
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $responseBytes = $webClient.UploadData($uri, "POST", $jsonBytes)
        $responseString = [System.Text.Encoding]::UTF8.GetString($responseBytes)
        
        # 尝试解析 JSON 响应
        try {
            $responseObj = $responseString | ConvertFrom-Json -ErrorAction Stop
            return @{ success = $true; result = $responseObj }
        } catch {
            # 如果不是 JSON，返回原始字符串
            return @{ success = $true; result = $responseString }
        }
    } catch [System.Net.WebException] {
        $errorMsg = $_.Exception.Message
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDescription = $_.Exception.Response.StatusDescription
            $errorMsg = "HTTP $statusCode : $statusDescription"
            
            # 尝试读取错误响应
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $errorResponse = $reader.ReadToEnd()
                $reader.Close()
                $errorMsg += " - $errorResponse"
            } catch {
                # 忽略读取错误
            }
        }
        
        return @{ success = $false; error = $errorMsg }
    } catch {
        return @{ success = $false; error = $_.Exception.Message }
    } finally {
        if ($webClient -ne $null) {
            $webClient.Dispose()
        }
    }
}

# 异步调用封装
function Start-AsyncApiCall {
    param(
        [string]$Endpoint,
        [hashtable]$Body = $null,
        [scriptblock]$OnSuccess,
        [scriptblock]$OnError,
        [int]$TimeoutSeconds = 120
    )
    
    $jobScript = {
        param($Config, $Endpoint, $Body, $TimeoutSeconds)
        
        # 在作业中重新定义函数
        function Invoke-TTSApiInJob {
            param(
                [string]$Endpoint,
                [hashtable]$Body = $null,
                [int]$TimeoutSeconds = 120
            )
            
            $uri = "$($Config.base_url)$Endpoint"
            
            try {
                # 使用 WebClient 确保 UTF-8 编码
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("Content-Type", "application/json; charset=utf-8")
                $webClient.Encoding = [System.Text.Encoding]::UTF8
                
                # 转换为 JSON
                $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
                
                # 发送请求
                $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
                $responseBytes = $webClient.UploadData($uri, "POST", $jsonBytes)
                $responseString = [System.Text.Encoding]::UTF8.GetString($responseBytes)
                
                # 尝试解析 JSON 响应
                try {
                    $responseObj = $responseString | ConvertFrom-Json -ErrorAction Stop
                    return @{ success = $true; result = $responseObj }
                } catch {
                    # 如果不是 JSON，返回原始字符串
                    return @{ success = $true; result = $responseString }
                }
            } catch [System.Net.WebException] {
                $errorMsg = $_.Exception.Message
                if ($_.Exception.Response) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    $statusDescription = $_.Exception.Response.StatusDescription
                    $errorMsg = "HTTP $statusCode : $statusDescription"
                }
                return @{ success = $false; error = $errorMsg }
            } catch {
                return @{ success = $false; error = $_.Exception.Message }
            } finally {
                if ($webClient -ne $null) {
                    $webClient.Dispose()
                }
            }
        }
        
        return Invoke-TTSApiInJob -Endpoint $Endpoint -Body $Body -TimeoutSeconds $TimeoutSeconds
    }
    
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $Script:Config, $Endpoint, $Body, $TimeoutSeconds
    
    # 注册作业完成事件
    Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
        $job = $Event.SourceEventArgs.Job
        if ($job.State -eq "Completed") {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            if ($result.success) {
                & $OnSuccess $result.result
            } else {
                & $OnError $result.error
            }
        } elseif ($job.State -eq "Failed") {
            Remove-Job -Job $job
            & $OnError "作业执行失败"
        }
    } | Out-Null
}

# ================= 事件绑定 =================
Write-Host "绑定事件..."

# 浏览模型目录
if ($BrowseModelButton -ne $null) {
    $BrowseModelButton.Add_Click({
        try {
            $path = Browse-Folder "选择模型目录"
            if ($path -and $ModelDirectoryTextBox -ne $null) { 
                $ModelDirectoryTextBox.Text = $path 
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Show-Error "浏览目录时出错: $errorMsg"
        }
    })
}

# 加载角色
if ($LoadCharacterButton -ne $null) {
    $LoadCharacterButton.Add_Click({
        $character_name = $CharacterNameTextBox.Text.Trim()
        $onnx_model_dir = $ModelDirectoryTextBox.Text.Trim()
        if (-not $character_name -or -not $onnx_model_dir) {
            Show-Error "请填写角色名称和模型目录"
            return
        }
        $Script:Config.recent_character = $character_name
        $Script:Config.recent_model_dir = $onnx_model_dir
        Save-Config

        Set-Status "正在调用 /load_character ..."
        
        $body = @{
            character_name = $character_name
            onnx_model_dir = $onnx_model_dir
        }
        
        Start-AsyncApiCall -Endpoint "/load_character" -Body $body -OnSuccess {
            param($result)
            Set-Status "/load_character 调用成功"
            Show-Info "角色加载成功: $character_name"
        } -OnError {
            param($error)
            Set-Status "/load_character 失败: $error"
            Show-Error "角色加载失败: $error"
        }
    })
}

# 卸载角色
if ($UnloadCharacterButton -ne $null) {
    $UnloadCharacterButton.Add_Click({
        $character_name = $UnloadCharacterTextBox.Text.Trim()
        if (-not $character_name) { Show-Error "请填写角色名称"; return }
        Set-Status "正在调用 /unload_character ..."
        
        $body = @{
            character_name = $character_name
        }
        
        Start-AsyncApiCall -Endpoint "/unload_character" -Body $body -OnSuccess {
            param($result)
            Set-Status "/unload_character 调用成功"
            Show-Info "角色卸载成功: $character_name"
        } -OnError {
            param($error)
            Set-Status "/unload_character 失败: $error"
            Show-Error "角色卸载失败: $error"
        }
    })
}

# 浏览参考音频文件
if ($BrowseAudioButton -ne $null) {
    $BrowseAudioButton.Add_Click({
        try {
            $file = Browse-File "音频文件 (*.wav;*.mp3;*.flac;*.ogg)|*.wav;*.mp3;*.flac;*.ogg|所有文件 (*.*)|*.*" "选择音频文件"
            if ($file -and $AudioFilePathTextBox -ne $null) { 
                $AudioFilePathTextBox.Text = $file 
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Show-Error "浏览音频文件时出错: $errorMsg"
        }
    })
}

# 保存参考音频配置
if ($SaveReferenceConfigButton -ne $null) {
    $SaveReferenceConfigButton.Add_Click({
        $Script:Config.recent_ref_character = $ReferenceCharacterTextBox.Text.Trim()
        $Script:Config.recent_audio_path = $AudioFilePathTextBox.Text.Trim()
        $Script:Config.recent_audio_text = $AudioTextTextBox.Text.Trim()
        Save-Config
        Show-Info "参考音频配置已保存"
    })
}

# 设置参考音频
if ($SetReferenceAudioButton -ne $null) {
    $SetReferenceAudioButton.Add_Click({
        $character_name = $ReferenceCharacterTextBox.Text.Trim()
        $audio_path = $AudioFilePathTextBox.Text.Trim()
        $audio_text = $AudioTextTextBox.Text.Trim()
        if (-not ($character_name -and $audio_path -and $audio_text)) {
            Show-Error "请填写角色名称、音频文件和音频文本"
            return
        }
        $Script:Config.recent_ref_character = $character_name
        $Script:Config.recent_audio_path = $audio_path
        $Script:Config.recent_audio_text = $audio_text
        Save-Config

        Set-Status "正在调用 /set_reference_audio ..."
        
        $body = @{
            character_name = $character_name
            audio_path = $audio_path
            audio_text = $audio_text
        }
        
        Start-AsyncApiCall -Endpoint "/set_reference_audio" -Body $body -OnSuccess {
            param($result)
            Set-Status "/set_reference_audio 调用成功"
            Show-Info "参考音频设置成功"
        } -OnError {
            param($error)
            Set-Status "/set_reference_audio 失败: $error"
            Show-Error "参考音频设置失败: $error"
        }
    })
}

# 浏览保存路径
if ($BrowseSavePathButton -ne $null) {
    $BrowseSavePathButton.Add_Click({
        try {
            $file = Browse-SaveFile
            if ($file -and $SavePathTextBox -ne $null) { 
                $SavePathTextBox.Text = $file 
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Show-Error "设置保存路径时出错: $errorMsg"
        }
    })
}

# 停止
if ($StopTTSButton -ne $null) {
    $StopTTSButton.Add_Click({
        Set-Status "正在调用 /stop ..."
        
        Start-AsyncApiCall -Endpoint "/stop" -Body @{} -OnSuccess {
            param($result)
            Set-Status "/stop 调用成功"
            Show-Info "TTS 已停止"
        } -OnError {
            param($error)
            Set-Status "/stop 失败: $error"
            Show-Error "停止 TTS 失败: $error"
        }
    })
}

# 开始 TTS (保存)
if ($StartTTSButton -ne $null) {
    $StartTTSButton.Add_Click({
        try {
            $character_name = $TTSCharacterTextBox.Text.Trim()
            $text = $TTSTextTextBox.Text.Trim()
            
            # 安全地获取保存路径
            $save_path = ""
            if ($SavePathTextBox -ne $null) {
                $save_path = $SavePathTextBox.Text.Trim()
            }
            
            if (-not ($character_name -and $text)) { 
                Show-Error "请填写角色名称和文本"
                return 
            }
            
            if ($save_path) { 
                $Script:Config.recent_tts_save = $save_path 
            }
            $Script:Config.recent_tts_character = $character_name
            $Script:Config.recent_tts_text = $text
            Save-Config

            Set-Status "正在调用 /tts ..."
            
            $body = @{ 
                character_name = $character_name
                text = $text
                split_sentence = [bool]$SplitSentenceCheckBox.IsChecked
            }
            
            if ($save_path) {
                $body.save_path = $save_path
            }
            
            Start-AsyncApiCall -Endpoint "/tts" -Body $body -TimeoutSeconds 300 -OnSuccess {
                param($result)
                Set-Status "/tts 调用完成"
                Show-Info "TTS 转换完成。请检查服务器上指定的保存路径或 API 返回。"
            } -OnError {
                param($error)
                Set-Status "/tts 失败: $error"
                Show-Error "TTS 失败: $error"
            }
        } catch {
            Show-Error "开始 TTS 时出错: $($_.Exception.Message)"
            Set-Status "开始 TTS 时出错"
        }
    })
}

# 朗读文本 - 保存到缓存目录
if ($SpeakTextButton -ne $null) {
    $SpeakTextButton.Add_Click({
        try {
            $character_name = $TTSCharacterTextBox.Text.Trim()
            $text = $TTSTextTextBox.Text.Trim()
            
            if (-not $character_name) { 
                Set-Status "请填写角色名称"
                return 
            }
            if (-not $text) { 
                Set-Status "请输入要朗读的文本"
                return 
            }
            
            # 保存配置
            $Script:Config.recent_tts_character = $character_name
            $Script:Config.recent_tts_text = $text
            Save-Config

            Set-Status "正在请求TTS音频..."
            
            # 获取音频缓存目录
            $cacheDir = Get-AudioCacheDir
            
            # 生成安全的文件名
            $safeText = Get-SafeFileName $text
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileName = "${safeText}_${timestamp}.wav"
            $audioFile = Join-Path $cacheDir $fileName
            
            # 使用同步调用确保文件生成后再播放
            $body = @{
                character_name = $character_name
                text = $text
                split_sentence = [bool]$SplitSentenceCheckBox.IsChecked
                save_path = $audioFile
            }
            
            $result = Invoke-TTSApi -Endpoint "/tts" -Body $body -TimeoutSeconds 300
            
            if ($result.success) {
                Set-Status "TTS转换完成，检查文件..."
                
                # 等待文件生成，最多等待10秒
                $maxWaitTime = 10000  # 10秒
                $waitInterval = 500   # 每次等待500毫秒
                $totalWaited = 0
                $fileExists = $false
                
                while ($totalWaited -lt $maxWaitTime -and -not $fileExists) {
                    Start-Sleep -Milliseconds $waitInterval
                    $totalWaited += $waitInterval
                    $fileExists = Test-Path $audioFile
                }
                
                if (Test-Path $audioFile) {
                    $fileInfo = Get-Item $audioFile
                    
                    # 检查文件是否有效（大于1KB）
                    if ($fileInfo.Length -lt 1024) {
                        Set-Status "音频文件过小，可能生成失败"
                        return
                    }
                    
                    Set-Status "正在播放音频..."
                    
                    try {
                        # 使用 SoundPlayer 播放音频
                        $player = New-Object System.Media.SoundPlayer
                        $player.SoundLocation = $audioFile
                        $player.Load()
                        $player.PlaySync()
                        $player.Dispose()
                        
                        Set-Status "播放完成 - 文件已保存到: $fileName"
                        
                    } catch {
                        Set-Status "播放失败"
                    }
                } else {
                    Set-Status "音频文件未生成"
                }
            } else {
                Set-Status "TTS请求失败"
            }
        } catch {
            Set-Status "朗读文本时出错"
        }
    })
}

# 浏览音频缓存目录
if ($BrowseAudioCacheDirButton -ne $null) {
    $BrowseAudioCacheDirButton.Add_Click({
        try {
            $path = Browse-Folder "选择音频缓存目录"
            if ($path -and $AudioCacheDirTextBox -ne $null) { 
                $AudioCacheDirTextBox.Text = $path 
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Show-Error "浏览目录时出错: $errorMsg"
        }
    })
}

# 更新音频缓存目录
if ($UpdateAudioCacheDirButton -ne $null) {
    $UpdateAudioCacheDirButton.Add_Click({
        $val = $AudioCacheDirTextBox.Text.Trim()
        if ($val) {
            $Script:Config.audio_cache_dir = $val
            Save-Config
            Set-Status "音频缓存目录已更新"
            
            # 尝试创建目录
            try {
                if (-not (Test-Path $val)) {
                    New-Item -ItemType Directory -Path $val -Force | Out-Null
                }
            } catch {
                Set-Status "创建目录失败，将使用默认目录"
                $Script:Config.audio_cache_dir = Join-Path $Script:ScriptDir "TTSAudioCache"
                Save-Config
            }
        } else {
            Set-Status "请输入有效的目录路径"
        }
    })
}

# 打开音频缓存目录
if ($OpenAudioCacheDirButton -ne $null) {
    $OpenAudioCacheDirButton.Add_Click({
        try {
            $cacheDir = Get-AudioCacheDir
            if (Test-Path $cacheDir) {
                Start-Process "explorer.exe" -ArgumentList $cacheDir
                Set-Status "已打开缓存目录"
            } else {
                Set-Status "缓存目录不存在"
            }
        } catch {
            Set-Status "打开目录失败"
        }
    })
}

# 清除参考音频缓存
if ($ClearCacheButton -ne $null) {
    $ClearCacheButton.Add_Click({
        Set-Status "正在调用 /clear_reference_audio_cache ..."
        
        Start-AsyncApiCall -Endpoint "/clear_reference_audio_cache" -Body @{} -OnSuccess {
            param($result)
            Set-Status "/clear_reference_audio_cache 调用成功"
            Show-Info "参考音频缓存已清除"
        } -OnError {
            param($error)
            Set-Status "/clear_reference_audio_cache 失败: $error"
            Show-Error "清除缓存失败: $error"
        }
    })
}

# 更新 API 地址
if ($UpdateApiButton -ne $null) {
    $UpdateApiButton.Add_Click({
        $val = $ApiUrlTextBox.Text.Trim()
        if ($val) {
            $Script:Config.base_url = $val
            Save-Config
            Set-Status "API 地址已更新"
        } else {
            Set-Status "请输入有效的 API 地址"
        }
    })
}

# 测试连接
if ($TestConnectionButton -ne $null) {
    $TestConnectionButton.Add_Click({
        Set-Status "正在测试连接..."
        
        $testScript = {
            param($baseUrl)
            try {
                $response = Invoke-WebRequest -Uri $baseUrl -TimeoutSec 5 -UseBasicParsing
                return @{ success = $true; result = "连接成功" }
            } catch {
                try {
                    $response = Invoke-WebRequest -Uri "$baseUrl/docs" -TimeoutSec 5 -UseBasicParsing
                    return @{ success = $true; result = "连接成功 (文档可访问)" }
                } catch {
                    return @{ success = $false; error = $_.Exception.Message }
                }
            }
        }
        
        $job = Start-Job -ScriptBlock $testScript -ArgumentList $Script:Config.base_url
        
        Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
            $job = $Event.SourceEventArgs.Job
            if ($job.State -eq "Completed") {
                $result = Receive-Job -Job $job
                Remove-Job -Job $job
                
                if ($result.success) {
                    Set-Status "连接测试成功"
                } else {
                    Set-Status "连接测试失败"
                }
            }
        } | Out-Null
    })
}

# 关闭窗口时保存配置
if ($window -ne $null) {
    $window.Closing.Add({
        Save-Config
    })

    Write-Host "显示窗口..."
    # 显示窗口
    $window.ShowDialog() | Out-Null
    Write-Host "窗口关闭"
} else {
    Write-Error "窗口创建失败，无法启动GUI"
    [System.Windows.MessageBox]::Show("窗口创建失败，无法启动GUI", "错误", "OK", "Error")
}