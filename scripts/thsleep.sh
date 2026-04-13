#!/bin/bash

echo "Sending sleep command to Thanatos..."

ssh oliver@thanatos "powershell -NoProfile -Command -" << 'EOF'
$signature = @"
[DllImport("user32.dll")]
public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);
"@
$type = Add-Type -MemberDefinition $signature -Name "Win32SendMessage" -Namespace "Win32" -PassThru
$type::SendMessage(0xffff, 0x0112, 0xf170, 2)
EOF
