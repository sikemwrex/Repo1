@{
    SchemaVersion = '1.0'
    VMName        = 'CU-VM01'
    Hypervisor    = 'Hyper-V'
    Generation    = 2

    Compute = @{
        ProcessorCount = 4
        StartupMemoryGB = 8
        PreferredMemoryGB = 12
        DynamicMemory = $false
    }

    Storage = @{
        VHDType = 'Dynamic'
        SizeGB  = 100
    }

    Firmware = @{
        SecureBoot = $true
        VirtualTPM = $true
    }

    Network = @{
        Mode = 'InternalNAT'
        SwitchName = 'CU-NAT'
        # Subnet intentionally unresolved until Gate A inspects host/VPN routes.
        Subnet = $null
    }

    Identity = @{
        AdminUser = 'CUAdmin'
        OperatorUser = 'CUAgent'
        OperatorMustBeLocalAdmin = $false
    }

    Isolation = @{
        HostDriveRedirection = $false
        SharedFolders = $false
        SharedClipboardDuringBaseline = $false
        GuestServicesFileCopy = $false
    }

    Checkpoints = @(
        '00-WIN11-CLEAN',
        '01-WIN11-HARDENED',
        '02-CHATGPT-INSTALLED',
        '03-COMPUTER-USE-VERIFIED'
    )
}
