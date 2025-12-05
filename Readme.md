

# restore docker to default
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock autohide-time-modifier
killall Dock

# set docker to be instant
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0
killall Dock

# ignoring files at the global levels
git config --global core.excludesfile ~/.gitignore_global
echo ".DS_Store" >> ~/.gitignore_global


# Generate faster key repeat rate and delay shorter
# Do not want this, was not happy with it

# installing forticlient vpn
pay attention, take forticlient vpn only. not their entire shit/


# set your correct git user account
# on global
git config --global user.name "Andi Ion Oliver"
git config --global user.email "andioliverion@gmail.com"

# on work
git config --global user.name "Andi Ion Oliver"
git config --global user.email "andi@ardis.eu"

# restart codemeter wibu
sudo launchctl kickstart -k system/com.wibu.CodeMeter.Server
