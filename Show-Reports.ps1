$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Diagnostics.psm1') -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form=New-Object Windows.Forms.Form;$form.Text='TRMP - review local diagnostics';$form.Size=New-Object Drawing.Size(900,690);$form.StartPosition='CenterScreen'
$label=New-Object Windows.Forms.Label;$label.Text="Nothing is uploaded automatically. No Git/GitHub account is needed to get the report file.`r`nReview before sharing. GitHub Issues are PUBLIC. Never attach raw logs, saves or dumps.";$label.SetBounds(15,12,850,45);$form.Controls.Add($label)
$role=New-Object Windows.Forms.ComboBox;$role.DropDownStyle='DropDownList';$role.Items.AddRange(@('host','client'));$role.SelectedIndex=0;$role.SetBounds(15,60,130,25);$form.Controls.Add($role)
$prepare=New-Object Windows.Forms.Button;$prepare.Text='Prepare latest session';$prepare.SetBounds(155,58,190,29);$form.Controls.Add($prepare)
$folder=New-Object Windows.Forms.Button;$folder.Text='Open report folder';$folder.Enabled=$false;$folder.SetBounds(355,58,180,29);$form.Controls.Add($folder)
$list=New-Object Windows.Forms.ListBox;$list.SetBounds(15,95,850,85);$form.Controls.Add($list)
$text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ReadOnly=$true;$text.ScrollBars='Both';$text.WordWrap=$false;$text.Font=New-Object Drawing.Font('Consolas',10);$text.SetBounds(15,190,850,360);$form.Controls.Add($text)
$warning=New-Object Windows.Forms.CheckBox;$warning.Text='I reviewed this report. I understand that posting on GitHub makes it public.';$warning.SetBounds(15,558,850,25);$form.Controls.Add($warning)
$copy=New-Object Windows.Forms.Button;$copy.Text='Copy reviewed report';$copy.Enabled=$false;$copy.SetBounds(15,590,220,30);$form.Controls.Add($copy)
$github=New-Object Windows.Forms.Button;$github.Text='Open GitHub Issues (public)';$github.Enabled=$false;$github.SetBounds(245,590,250,30);$form.Controls.Add($github)
$status=New-Object Windows.Forms.Label;$status.Text='Reports stay local until you deliberately paste/upload them.';$status.SetBounds(15,625,850,22);$form.Controls.Add($status)
$script:reportPaths=@()
function Refresh-TrmpReports {
    $text.Clear();$warning.Checked=$false;$folder.Enabled=$false;$list.Items.Clear();$script:reportPaths=@()
    foreach($target in @('host','client')){
        $dir=Join-Path $PSScriptRoot "runtime\$target\reports";[void](Assert-TrmpPlainPath $dir)
        if(Test-Path -LiteralPath $dir){foreach($f in @(Get-ChildItem -LiteralPath $dir -File|Where-Object {$_.Name -cmatch '^TRMP-report-[a-f0-9-]{36}\.txt$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 20)){
            $script:reportPaths+=$f.FullName;[void]$list.Items.Add($target+' / '+$f.Name)
        }}
    }
    if($list.Items.Count){$list.SelectedIndex=0}
}
$list.Add_SelectedIndexChanged({
    $warning.Checked=$false
    $folder.Enabled=$list.SelectedIndex -ge 0
    if($list.SelectedIndex -ge 0){try{$text.Text=Read-TrmpBounded $script:reportPaths[$list.SelectedIndex] 262144}catch{$text.Text='Report could not be read safely.'}}
})
$warning.Add_CheckedChanged({$copy.Enabled=$github.Enabled=$warning.Checked -and $text.Text.StartsWith('TRMP DIAGNOSTIC REPORT')})
$prepare.Add_Click({
    try{
        $root=Join-Path $PSScriptRoot ('runtime\'+$role.SelectedItem)
        $session=Get-TrmpJson (Join-Path $root 'diagnostic-session.json');if(-not$session){throw 'No diagnostic session yet.'}
        $code=Get-TrmpProperty $session 'exitCode'
        [void](New-TrmpReport $root $session $code 'manual');Refresh-TrmpReports;$status.Text='Prepared locally. Review all contents before sharing.'
    }catch{$status.Text='Could not prepare a report. Start this mod build once, then try again.'}
})
$folder.Add_Click({if($list.SelectedIndex -ge 0){$path=Assert-TrmpPlainPath (Split-Path $script:reportPaths[$list.SelectedIndex] -Parent);Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList @('"'+$path+'"');$status.Text='Folder opened. Attach only the reviewed TRMP-report .txt using your chosen reporting channel.'}})
$copy.Add_Click({[Windows.Forms.Clipboard]::SetText($text.Text);$status.Text='Copied. Choose your recipient/channel yourself. GitHub/Steam posts are public.'})
$github.Add_Click({Start-Process 'https://github.com/Pox101/Terminator-Resistance-Multiplayer/issues/new';$status.Text='Browser opened. Nothing submitted. Paste the reviewed report and reproduction steps yourself.'})
Refresh-TrmpReports
[void]$form.ShowDialog()
