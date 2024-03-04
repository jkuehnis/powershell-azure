#connect Azure account
Function Connect-azure{
    if(!(Get-AzContext)){
        Connect-AzAccount
    }
}


Function get-AzureSQLandVm{
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Linux","Windows","AllOS")]
        [string]$OSType
    )


    $global:arrayvm = @()
    $global:arraysql = @()
    $global:arrayAzSqlInstance = @()
    $subscriptions = Get-AzSubscription
    
    Foreach($sub in $subscriptions){
        Set-AzContext -Subscription $sub.Name

        $sql = Get-AzSqlServer
        $global:arraysql += $sql
        $ManagedInstanceSQL =  Get-AzSqlInstance
        $global:arrayAzSqlInstance += $ManagedInstanceSQL


        $vm = Get-AzVM *


        $vm | %{$filterpurpose += Out-String -InputObject $_}
        $vm | %{
           
                $properties = @{
                    Name = $_.Name
                    LicenseType = $_.LicenseType
                    SubscriptionId = $sub.Id
                    Subscription = $sub.Name
                    Location = $_.Location
                    OsType = $_.StorageProfile.osDisk.osType
                    RessourceGroup = $_.ResourceGroupName
                    vmid = $_.VmId
                    Offer = $_.StorageProfile.ImageReference.Offer
                    sku = $_.StorageProfile.ImageReference.sku
                    ExactVersion = $_.StorageProfile.ImageReference.ExactVersion
                    Publisher = $_.StorageProfile.ImageReference.Publisher
                }
                $o = New-Object psobject -Property $properties; $o
                $global:arrayvm += $o
        }
    }

    #throw output by filter
    if($OSType -eq 'AllOs') {
        $global:arrayvm  | Format-Table
        $global:csv= $global:arrayvm
    }Else{
        $global:arrayvm | ? {$_.OsType -eq $OSType} | Format-Table
        $global:csv= $global:arrayvm | ? {$_.OsType -eq $OSType} 
    }
    #exportvm
    $CsvPath = "$env:TEMP\ExportAzureVM_$((Get-Date).ToString('dd-MM-yyyy_hh-mm-ss')).csv"
    $csv | Export-Csv -Path $CsvPath
    Write-Host "CSV export VM: "  -NoNewline; Write-Host  $CsvPath -ForegroundColor Green

    #exportsql
    $CsvPathSQL = "$env:TEMP\ExportAzureSQL_$((Get-Date).ToString('dd-MM-yyyy_hh-mm-ss')).csv"
    $global:arraysql | Export-Csv -Path $CsvPathSQL
    Write-Host "CSV expor SQL: "  -NoNewline; Write-Host  $CsvPathSQL -ForegroundColor Cyan

    #exportManagedInstanceSQL
    $CsvPathManagedInst = "$env:TEMP\ExportAzureManagedSQLInstance_$((Get-Date).ToString('dd-MM-yyyy_hh-mm-ss')).csv"
    $global:arrayAzSqlInstance | Export-Csv -Path $CsvPathManagedInst
    Write-Host "CSV expor SQL Managed Instance: "  -NoNewline; Write-Host  $CsvPathManagedInst -ForegroundColor Yellow


    try{
        Invoke-Expression "explorer '/select,$CsvPath'"
    }catch{
    }
}

Connect-azure
get-AzureSQLandVm -OSType Windows


Function Get-ServerwithoutBenefitLicense{
#get VM's without hybrid benefit license
    if(!($global:arrayvm)){
        get-AzureSQLandVm -OSType Windows
    }
    $global:arrayvm | ? {($_.OsType -eq 'Windows') -and ($_.LicenseType -notmatch 'Windows') } | ft
}


Function Update-WindowsLicenseAzureSingleHost{
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname
    )

    if(!($global:arrayvm)){
        get-AzureSQLandVm -OSType Windows
    }
    
    $vmname = $Hostname

    If($global:arrayvm.name -notcontains $vmname){
        write-host "VM $vmname name not found..." -ForegroundColor Red
        return
    }

    
    If(($global:arrayvm |? {$_.Name -eq $vmname}).OsType -ne 'Windows'){
        write-host "VM $vmname Os is not windows..." -ForegroundColor Red
        return
    }

    
    Set-AzContext -Subscription ($global:arrayvm | ? {($_.Name -eq $vmname)}).Subscription

    $vm = Get-AzVM -ResourceGroup ($global:arrayvm | ? {($_.Name -eq $vmname)}).RessourceGroup -Name ($global:arrayvm | ? {($_.Name -eq $vmname)}).Name
    if($vm.LicenseType -match 'Windows'){
        Write-Host "There is already a License Type set on $vmname :" $vm.LicenseType
        $response = read-host "Press key to continue y/n (default n)"
        switch ($response)                         
        {                        
            y {}                        
            n {return}                        
            Default {return}                        
        }            
    
    }
    $vm.LicenseType = "Windows_Server"
    Update-AzVM -ResourceGroupName ($global:arrayvm | ? {($_.Name -eq $vmname)}).RessourceGroup -VM $vm
}


Function Update-WindowsLicenseAzureAllHost{
    
    if(!($global:arrayvm)){
        get-AzureSQLandVm -OSType Windows
    }
    
    $serversnolicense = $global:arrayvm | ? {($_.OsType -eq 'Windows') -and ($_.LicenseType -notmatch 'Windows') }

    Foreach($obj in $serversnolicense){
    
        Set-AzContext -Subscription $obj.Subscription

        $vm = Get-AzVM -ResourceGroup $obj.RessourceGroup -Name $obj.Name
        if($vm.LicenseType -match 'Windows'){
            Write-Host "There is already a License Type set on" $obj.Name ":" $vm.LicenseType
            $response = read-host "Press key to continue y/n (default n)"
            switch ($response)                         
            {                        
                y {}                        
                n {continue}                        
                Default {continue}                        
            }            
        
        }
        $vm.LicenseType = "Windows_Server"
        Update-AzVM -ResourceGroupName $obj.RessourceGroup -VM $vm
    }
}
