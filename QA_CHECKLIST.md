# QA_CHECKLIST.md — Samsung TV Remote (iOS)

## 🌐 Network & Discovery
- [ ] App requests local network permission on first launch (iOS 14+ privacy prompt)
- [ ] App discovers Samsung TV on same Wi-Fi subnet within 10 seconds
- [ ] Simulator shows "Wi-Fi required" — all testing done on real device
- [ ] Saved TVs appear on relaunch without re-scanning
- [ ] Manual IP entry connects to TV successfully
- [ ] Wake on LAN powers on TV from standby
- [ ] TV powered off mid-session shows reconnecting state gracefully

## 🔑 Pairing
- [ ] First connection shows "Allow?" prompt on TV screen
- [ ] App shows 30-second countdown pairing UI
- [ ] Token is persisted — no re-pairing on second launch
- [ ] "Forget Token" in Settings forces re-pairing next connect
- [ ] Pairing rejection shows descriptive error in app

## 🕹️ Remote Controls
- [ ] D-pad UP / DOWN / LEFT / RIGHT each work on TV UI
- [ ] D-pad center (OK/ENTER) confirms TV selection
- [ ] Volume UP / DOWN change TV volume
- [ ] Mute toggles audio on TV
- [ ] Channel UP / DOWN change TV channel
- [ ] Channel List opens channel browser on TV
- [ ] Power button (tap) toggles TV standby
- [ ] Power button (long press 0.8s) turns TV off
- [ ] Number keys 0–9 navigate to channels
- [ ] PLAY / PAUSE / FF / REWIND / STOP control active media
- [ ] RED / GREEN / YELLOW / BLUE color buttons work
- [ ] HOME navigates to TV home screen
- [ ] MENU opens TV menu
- [ ] GUIDE opens EPG
- [ ] SOURCE opens input source selection
- [ ] SMART HUB opens Samsung Smart Hub
- [ ] App from App Launcher launches on TV

## ⚠️ Edge Cases
- [ ] App auto-reconnects after TV wakes from sleep
- [ ] Rapid tapping (10+ presses/sec) does not crash or freeze
- [ ] App shows "Wi-Fi required" message when on cellular
- [ ] Device rotation preserves layout and WebSocket connection
- [ ] Background for 5+ minutes: connection restored on foreground
- [ ] Two iPhones connected to same TV — both send keys correctly
- [ ] Malformed TV WebSocket JSON does not crash app
- [ ] Works on iPhone SE 2nd gen (small screen layout)
- [ ] Works on iPad in landscape (adaptive two-column layout)

## 🎨 UI / UX
- [ ] Haptic feedback fires on every button press
- [ ] Connection dot updates within 1 second of state change
- [ ] Number pad expand/collapse animation is smooth (60fps)
- [ ] App Launcher sheet scrolls smoothly with app icons
- [ ] Dark Mode renders all elements correctly
- [ ] Dynamic Type: text scales without breaking layout
- [ ] VoiceOver: all buttons have accessibility labels
- [ ] No hardcoded strings — all in Localizable.strings
