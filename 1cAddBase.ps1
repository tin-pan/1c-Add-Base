# Загрузка необходимых сборок
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Создание XAML разметки
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Управление файлами 1С на компьютерах пользователей"
        Height="850" Width="1100" WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize">
    
    <DockPanel LastChildFill="True">
        
        <!-- Верхняя панель с основным содержимым -->
        <StackPanel DockPanel.Dock="Top" Margin="10">
            
            <!-- Список пользователей -->
            <Label Content="Список пользователей (каждая строка - часть displayName или cn):" 
                   FontWeight="Bold" Margin="0,0,0,5"/>
            <TextBox Name="txtUsers" Height="140" AcceptsReturn="True" TextWrapping="Wrap" 
                     VerticalScrollBarVisibility="Auto" FontFamily="Consolas" Margin="0,0,0,15"/>
            
            <!-- Параметр Name -->
            <Label Content="Параметр Name (будет добавлен как [name]):" 
                   FontWeight="Bold" Margin="0,0,0,5"/>
            <TextBox Name="txtName" Height="35" FontFamily="Consolas" Margin="0,0,0,15"/>
            
            <!-- Параметр Base -->
            <Label Content="Параметр Base:" 
                   FontWeight="Bold" Margin="0,0,0,5"/>
            <TextBox Name="txtBase" Height="35" FontFamily="Consolas" Margin="0,0,0,15"/>
            
            <!-- Кнопка Запустить -->
            <StackPanel Orientation="Horizontal" Margin="0,0,0,15">
                <Button Name="btnRun" Background="#27AE60" Foreground="White" FontWeight="Bold" 
                        FontSize="14" Padding="15,8" Cursor="Hand" Width="120">
                    <TextBlock>▶ Запустить</TextBlock>
                </Button>
            </StackPanel>
        </StackPanel>
        
        <!-- Нижняя панель с логом -->
        <Grid DockPanel.Dock="Bottom">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <Label Grid.Row="0" Content="Лог выполнения:" FontWeight="Bold" Margin="10,0,0,5"/>
            
            <TextBox Grid.Row="1" Name="txtLog" IsReadOnly="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     Background="#F8F9F9" FontFamily="Consolas" FontSize="11" 
                     Margin="10,0,10,10" MinHeight="300"/>
            
            <StatusBar Grid.Row="2" Background="#ECF0F1" Height="30">
                <StatusBarItem>
                    <TextBlock Name="lblStatus" Foreground="#2C3E50" FontWeight="Bold">Готов к работе</TextBlock>
                </StatusBarItem>
            </StatusBar>
        </Grid>
    </DockPanel>
</Window>
"@

# Глобальные переменные для элементов управления
$script:txtUsers = $null
$script:txtName = $null
$script:txtBase = $null
$script:txtLog = $null
$script:lblStatus = $null
$script:btnRun = $null
$script:window = $null

# Функция логирования (потокобезопасная)
function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $emoji = switch ($Type) {
        "SUCCESS" { "✅" }
        "WARNING" { "⚠️" }
        "ERROR" { "❌" }
        default { "📌" }
    }
    $logMessage = "$emoji [$timestamp] [$Type] $Message"
    if ($script:txtLog -and $script:txtLog.Dispatcher) {
        $script:txtLog.Dispatcher.Invoke([Action]{
            $script:txtLog.AppendText($logMessage + "`r`n")
            $script:txtLog.ScrollToEnd()
        })
    }
    if ($script:lblStatus -and $script:lblStatus.Dispatcher) {
        $script:lblStatus.Dispatcher.Invoke([Action]{ $script:lblStatus.Text = $Message })
    }
}

# Загрузка окна и инициализация элементов
try {
    $xmlReader = New-Object System.Xml.XmlNodeReader($xaml)
    $script:window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    
    $script:txtUsers = $script:window.FindName("txtUsers")
    $script:txtName = $script:window.FindName("txtName")
    $script:txtBase = $script:window.FindName("txtBase")
    $script:txtLog = $script:window.FindName("txtLog")
    $script:lblStatus = $script:window.FindName("lblStatus")
    $script:btnRun = $script:window.FindName("btnRun")
    
    Write-Log "Программа запущена. Введите данные и нажмите 'Запустить'." -Type "INFO"
    Write-Log "Требуется модуль ActiveDirectory." -Type "INFO"
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Write-Log "Модуль ActiveDirectory найден" -Type "SUCCESS"
    } else {
        Write-Log "Модуль ActiveDirectory не найден! Установите RSAT Tools." -Type "WARNING"
    }
    
    # Обработчик кнопки
    if ($script:btnRun) {
        $script:btnRun.Add_Click({
            # Проверка активности кнопки
            if ($script:btnRun.IsEnabled -eq $false) {
                [System.Windows.Forms.MessageBox]::Show("Обработка уже выполняется. Подождите.", "Внимание")
                return
            }
            
            $usersText = $script:txtUsers.Text
            $nameValue = $script:txtName.Text.Trim()
            $baseValue = $script:txtBase.Text.Trim()
            
            if ([string]::IsNullOrWhiteSpace($usersText)) { Write-Log "ОШИБКА: Список пользователей пуст!" -Type "ERROR"; return }
            if ([string]::IsNullOrWhiteSpace($nameValue)) { Write-Log "ОШИБКА: Параметр Name не может быть пустым!" -Type "ERROR"; return }
            if ([string]::IsNullOrWhiteSpace($baseValue)) { Write-Log "ОШИБКА: Параметр Base не может быть пустым!" -Type "ERROR"; return }
            
            $usersList = $usersText -split "`r`n" | Where-Object { $_.Trim() -ne "" }
            
            # Блокируем интерфейс
            $script:btnRun.IsEnabled = $false
            $script:btnRun.Content = "⏳ Выполняется..."
            
            $dispatcher = $script:window.Dispatcher
            
            # Скриптблок для фонового выполнения
            $scriptBlock = {
                param($dispatcher, $writeLogFunc, $btn, $users, $nameParam, $baseParam)
                
                function Log($Message, $Type) { & $writeLogFunc -Message $Message -Type $Type }
                
                function UnlockUI {
                    $dispatcher.Invoke({
                        $btn.IsEnabled = $true
                        $btn.Content = "▶ Запустить"
                    }, 'Normal')
                }
                
                # ---- Вспомогательные функции ----
                function Get-ADPropertyString($PropertyValue) {
                    try {
                        if ($null -eq $PropertyValue) { return "" }
                        if ($PropertyValue -is [System.Collections.IEnumerable] -and -not ($PropertyValue -is [string])) {
                            $enumerator = $PropertyValue.GetEnumerator()
                            if ($enumerator.MoveNext()) { return $enumerator.Current.ToString() }
                            return ""
                        }
                        return $PropertyValue.ToString()
                    }
                    catch { return "" }
                }
                
                function Find-ADUser($SearchString) {
                    try {
                        $uniqueUsersHash = @{}
                        $filterDisplayName = "DisplayName -like '*$SearchString*'"
                        $usersByDisplayName = Get-ADUser -Filter $filterDisplayName -Properties DisplayName, SamAccountName, CN -ErrorAction Stop
                        if ($usersByDisplayName) {
                            $usersArray = if ($usersByDisplayName -is [array]) { $usersByDisplayName } else { @($usersByDisplayName) }
                            foreach ($user in $usersArray) {
                                $samAccountName = Get-ADPropertyString $user.SamAccountName
                                if (-not [string]::IsNullOrWhiteSpace($samAccountName) -and -not $uniqueUsersHash.ContainsKey($samAccountName)) {
                                    $uniqueUsersHash[$samAccountName] = $user
                                }
                            }
                        }
                        $filterCN = "CN -like '*$SearchString*'"
                        $usersByCN = Get-ADUser -Filter $filterCN -Properties DisplayName, SamAccountName, CN -ErrorAction Stop
                        if ($usersByCN) {
                            $usersArray = if ($usersByCN -is [array]) { $usersByCN } else { @($usersByCN) }
                            foreach ($user in $usersArray) {
                                $samAccountName = Get-ADPropertyString $user.SamAccountName
                                if (-not [string]::IsNullOrWhiteSpace($samAccountName) -and -not $uniqueUsersHash.ContainsKey($samAccountName)) {
                                    $uniqueUsersHash[$samAccountName] = $user
                                }
                            }
                        }
                        $uniqueUsers = @($uniqueUsersHash.Values)
                        if ($uniqueUsers.Count -eq 0) { return $null }
                        elseif ($uniqueUsers.Count -eq 1) { return $uniqueUsers[0] }
                        else {
                            $userList = ($uniqueUsers | ForEach-Object { 
                                $name = Get-ADPropertyString $_.SamAccountName
                                "$name (displayName: $($_.DisplayName))" 
                            }) -join "; "
                            $errorMessage = "Найдено несколько пользователей ($($uniqueUsers.Count)) по строке '$SearchString': $userList"
                            Log -Message $errorMessage -Type "ERROR"
                            throw $errorMessage
                        }
                    }
                    catch {
                        if ($_.Exception.Message -match "Найдено несколько пользователей") { throw $_ }
                        else {
                            $errorMessage = "Ошибка при поиске пользователя '$SearchString': $($_.Exception.Message)"
                            Log -Message $errorMessage -Type "ERROR"
                            throw $errorMessage
                        }
                    }
                }
                
                function Test-ComputerAvailability($ComputerName) {
                    try { return (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop) }
                    catch { return $false }
                }
                
                function Check-BaseInFile($FilePath, $BaseString) {
                    if (-not (Test-Path $FilePath)) { return $null }
                    try {
                        $content = Get-Content $FilePath -ErrorAction Stop
                        for ($i = 0; $i -lt $content.Count; $i++) {
                            if ($content[$i] -match '^\s*\[(.*?)\]\s*$') {
                                $currentName = $matches[1]
                                if ($i + 1 -lt $content.Count -and $content[$i + 1] -eq $BaseString) {
                                    return @{ Found = $true; OldName = $currentName }
                                }
                            }
                        }
                        return @{ Found = $false; OldName = $null }
                    }
                    catch {
                        Log -Message "Ошибка при чтении файла $FilePath : $($_.Exception.Message)" -Type "ERROR"
                        return $null
                    }
                }
                
                # ИСПРАВЛЕННАЯ ФУНКЦИЯ Add-ToFile (без автоматического создания файла)
                function Add-ToFile($FilePath, $NameValue, $BaseValue) {
                    # Проверяем существование файла
                    if (-not (Test-Path $FilePath)) {
                        return @{
                            Success = $false
                            Message = "Файл не существует: $FilePath"
                            AlreadyExists = $false
                        }
                    }
                    
                    try {
                        $checkResult = Check-BaseInFile -FilePath $FilePath -BaseString $BaseValue
                        if ($checkResult -and $checkResult.Found) {
                            return @{
                                Success = $false
                                Message = "Данная база уже присутствует в списке под именем '$($checkResult.OldName)'"
                                AlreadyExists = $true
                            }
                        }
                        
                        $nameLine = "[$NameValue]"
                        Add-Content -Path $FilePath -Value $nameLine -ErrorAction Stop
                        Add-Content -Path $FilePath -Value $BaseValue -ErrorAction Stop
                        
                        return @{
                            Success = $true
                            Message = "Успешно добавлено: $nameLine"
                            AlreadyExists = $false
                        }
                    }
                    catch {
                        return @{
                            Success = $false
                            Message = "Ошибка при записи в файл: $($_.Exception.Message)"
                            AlreadyExists = $false
                        }
                    }
                }
                
                function Show-SummaryReport {
                    Log -Message "╔════════════════════════════════════════════════════════════════════════════╗" -Type "INFO"
                    Log -Message "║                          ИТОГОВЫЙ ОТЧЁТ ПО ВСЕМ ПОЛЬЗОВАТЕЛЯМ               ║" -Type "INFO"
                    Log -Message "╚════════════════════════════════════════════════════════════════════════════╝" -Type "INFO"
                    $allResults = @($script:resultsList)
                    if ($allResults.Count -eq 0) {
                        Log -Message "Нет данных для отображения" -Type "WARNING"
                        return
                    }
                    $successResults = $allResults | Where-Object { $_.Status -eq "SUCCESS" }
                    $skipResults    = $allResults | Where-Object { $_.Status -eq "SKIP" }
                    $errorResults   = $allResults | Where-Object { $_.Status -eq "ERROR" }
                    $successCount = @($successResults).Count
                    $skipCount    = @($skipResults).Count
                    $errorCount   = @($errorResults).Count
                    
                    if ($successCount -gt 0) {
                        Log -Message "✅ УСПЕШНО ОБРАБОТАНО ($successCount):" -Type "SUCCESS"
                        foreach ($result in $successResults) { Log -Message "   $($result.UserIdentifier) -> $($result.Message)" -Type "SUCCESS" }
                    }
                    if ($skipCount -gt 0) {
                        Log -Message "⚠️ ПРОПУЩЕНО (УЖЕ СУЩЕСТВУЮТ) ($skipCount):" -Type "WARNING"
                        foreach ($result in $skipResults) { Log -Message "   $($result.UserIdentifier) -> $($result.Message)" -Type "WARNING" }
                    }
                    if ($errorCount -gt 0) {
                        Log -Message "❌ ОШИБКИ ($errorCount):" -Type "ERROR"
                        foreach ($result in $errorResults) { Log -Message "   $($result.UserIdentifier) -> $($result.Message)" -Type "ERROR" }
                    }
                    Log -Message "╔════════════════════════════════════════════════════════════════════════════╗" -Type "INFO"
                    Log -Message "║ СВОДКА:                                                                     ║" -Type "INFO"
                    Log -Message "║   ✅ Успешно:      $successCount                                                        ║" -Type "INFO"
                    Log -Message "║   ⚠️ Пропущено:     $skipCount                                                        ║" -Type "INFO"
                    Log -Message "║   ❌ Ошибки:       $errorCount                                                        ║" -Type "INFO"
                    Log -Message "║   📊 Всего записей: $($allResults.Count)                                                        ║" -Type "INFO"
                    Log -Message "╚════════════════════════════════════════════════════════════════════════════╝" -Type "INFO"
                }
                
                # ---- Основной код ----
                try {
                    $script:resultsList = @()
                    Log -Message ("=" * 70) -Type "INFO"
                    Log -Message "Начало обработки. Всего пользователей: $($users.Count)" -Type "INFO"
                    Log -Message "Параметр Name: '$nameParam'" -Type "INFO"
                    Log -Message "Параметр Base: '$baseParam'" -Type "INFO"
                    Log -Message ("=" * 70) -Type "INFO"
                    
                    $successCount = 0; $failCount = 0; $skipCount = 0
                    $totalUsers = $users.Count; $currentUser = 0
                    
                    foreach ($userSearch in $users) {
                        $currentUser++
                        $userSearchTrimmed = $userSearch.Trim()
                        Log -Message "[$currentUser/$totalUsers] Обработка: $userSearchTrimmed" -Type "INFO"
                        
                        $userResult = @{ UserIdentifier = $userSearchTrimmed; Status = ""; Message = ""; Detail = "" }
                        $resultProcessed = $false
                        
                        try {
                            $adUser = Find-ADUser -SearchString $userSearchTrimmed
                            if (-not $adUser) {
                                $userResult.Status = "ERROR"; $userResult.Message = "Пользователь не найден в AD"
                                Log -Message "  -> Пользователь не найден в Active Directory" -Type "WARNING"
                                $failCount++; $resultProcessed = $true
                            }
                            else {
                                $samAccountName = Get-ADPropertyString $adUser.SamAccountName
                                $displayName = Get-ADPropertyString $adUser.DisplayName
                                if ([string]::IsNullOrWhiteSpace($samAccountName)) {
                                    $userResult.Status = "ERROR"; $userResult.Message = "Не удалось получить SamAccountName"
                                    Log -Message "  -> SamAccountName отсутствует" -Type "ERROR"
                                    $failCount++; $resultProcessed = $true
                                }
                                else {
                                    $computerName = "$samAccountName-h"
                                    $filePath = "\\$computerName\c$\Users\$samAccountName\AppData\Roaming\1C\1CEStart\ibases.v8i"
                                    Log -Message "  -> Найден пользователь: $samAccountName ($displayName)" -Type "INFO"
                                    Log -Message "  -> Имя компьютера: $computerName" -Type "INFO"
                                    
                                    if (-not (Test-ComputerAvailability -ComputerName $computerName)) {
                                        $userResult.Status = "ERROR"; $userResult.Message = "Компьютер недоступен"
                                        Log -Message "  -> Компьютер $computerName не отвечает на ping" -Type "ERROR"
                                        $failCount++; $resultProcessed = $true
                                    }
                                    else {
                                        Log -Message "  -> Компьютер доступен" -Type "SUCCESS"
                                        $addResult = Add-ToFile -FilePath $filePath -NameValue $nameParam -BaseValue $baseParam
                                        if ($addResult.Success) {
                                            $userResult.Status = "SUCCESS"; $userResult.Message = "Успешно добавлено: [$nameParam]"
                                            Log -Message "  -> $($addResult.Message)" -Type "SUCCESS"
                                            $successCount++; $resultProcessed = $true
                                        }
                                        elseif ($addResult.AlreadyExists) {
                                            $userResult.Status = "SKIP"; $userResult.Message = $addResult.Message
                                            Log -Message "  -> $($addResult.Message)" -Type "WARNING"
                                            $skipCount++; $resultProcessed = $true
                                        }
                                        else {
                                            $userResult.Status = "ERROR"; $userResult.Message = $addResult.Message
                                            Log -Message "  -> $($addResult.Message)" -Type "ERROR"
                                            $failCount++; $resultProcessed = $true
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            if (-not $resultProcessed) {
                                $userResult.Status = "ERROR"; $userResult.Message = $_.Exception.Message
                                Log -Message "  -> $($_.Exception.Message)" -Type "ERROR"
                                $failCount++; $resultProcessed = $true
                            }
                        }
                        if ($resultProcessed -and $userResult.Status -ne "") { $script:resultsList += $userResult }
                        Log -Message "  -> ----------------------------------------" -Type "INFO"
                    }
                    
                    Log -Message ("=" * 70) -Type "INFO"
                    Log -Message "Обработка завершена!" -Type "SUCCESS"
                    Log -Message "✅ Успешно: $successCount" -Type "SUCCESS"
                    Log -Message "⚠️ Пропущено (уже есть): $skipCount" -Type "WARNING"
                    Log -Message "❌ Неудачно: $failCount" -Type "ERROR"
                    Log -Message ("=" * 70) -Type "INFO"
                    
                    Show-SummaryReport
                    
                    $dispatcher.Invoke({
                        [System.Windows.Forms.MessageBox]::Show(
                            "Обработка завершена!`n`n✅ Успешно: $successCount`n⚠️ Пропущено: $skipCount`n❌ Неудачно: $failCount",
                            "Результат выполнения",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        )
                    }, 'Normal')
                }
                catch {
                    Log -Message "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)" -Type "ERROR"
                }
                finally {
                    UnlockUI
                }
            }
            
            # Создаём runspace и запускаем
            $runspace = [RunspaceFactory]::CreateRunspace()
            $runspace.Open()
            $ps = [PowerShell]::Create()
            $ps.Runspace = $runspace
            
            $ps.AddScript($scriptBlock.ToString()) | Out-Null
            $ps.AddArgument($dispatcher) | Out-Null
            $ps.AddArgument(${function:Write-Log}) | Out-Null
            $ps.AddArgument($script:btnRun) | Out-Null
            $ps.AddArgument($usersList) | Out-Null
            $ps.AddArgument($nameValue) | Out-Null
            $ps.AddArgument($baseValue) | Out-Null
            
            $ps.BeginInvoke()
        })
    }
    else {
        Write-Log "ОШИБКА: Не удалось найти кнопку btnRun в XAML" -Type "ERROR"
    }
    
    $script:window.ShowDialog() | Out-Null
}
catch {
    Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
}
