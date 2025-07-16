Param(
  [string]$FilePath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

$form = New-Object System.Windows.Forms.Form
$form.Text = "oogit GUI"
$form.Size = New-Object System.Drawing.Size(280,160)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "File: $FilePath"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10,10)
$form.Controls.Add($label)

function Add-Button([string]$text, [System.Drawing.Point]$location, [scriptblock]$action) {
  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = $text
  $btn.Size = New-Object System.Drawing.Size(100,23)
  $btn.Location = $location
  $btn.Add_Click($action)
  $form.Controls.Add($btn)
}

Add-Button "Init" (New-Object System.Drawing.Point(10,40)) {
  $repo = [Microsoft.VisualBasic.Interaction]::InputBox("Repository URL","Init")
  if ($repo) {
    Start-Process "oogit" -ArgumentList "init `"$FilePath`" $repo" -Wait
  }
}

Add-Button "Checkout" (New-Object System.Drawing.Point(140,40)) {
  $repo = [Microsoft.VisualBasic.Interaction]::InputBox("Repository URL","Checkout")
  if ($repo) {
    Start-Process "oogit" -ArgumentList "checkout `"$FilePath`" $repo" -Wait
  }
}

Add-Button "Commit" (New-Object System.Drawing.Point(10,75)) {
  $msg = [Microsoft.VisualBasic.Interaction]::InputBox("Commit message","Commit")
  $args = "commit"
  if ($msg) { $args += " -m `"$msg`"" }
  Start-Process "oogit" -ArgumentList "$args `"$FilePath`"" -Wait
}

Add-Button "Update" (New-Object System.Drawing.Point(140,75)) {
  Start-Process "oogit" -ArgumentList "update `"$FilePath`"" -Wait
}

Add-Button "Reset" (New-Object System.Drawing.Point(10,110)) {
  $commit = [Microsoft.VisualBasic.Interaction]::InputBox("Tag or commit","Reset")
  if ($commit) {
    Start-Process "oogit" -ArgumentList "reset `"$FilePath`" $commit" -Wait
  }
}

$form.Topmost = $true
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()
