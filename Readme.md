

# restore docker to default
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock autohide-time-modifier
killall Dock

# set docker to be instant
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0
killall Dock


# Generate faster key repeat rate and delay shorter
# Do not want this, was not happy with it


