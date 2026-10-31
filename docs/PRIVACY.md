# Foldfleet — Privacy

## Version 1.0 (initial release)

Foldfleet works **fully offline**. It collects no personal data, has no
account system, no advertising, no analytics SDK, and makes no network
requests.

### What is stored, and where

All data stays on the user's device, in the app's Documents folder / UserDefaults:

| Data | Purpose | Stored where |
|---|---|---|
| Sound / music / haptics settings | Remember the player's preferences | UserDefaults (`@AppStorage`) |
| Match history (last 50 matches) | Show past results in History | `foldfleet-history.json` |
| Local statistics (wins, losses, accuracy) | Show progress on the menu | `foldfleet-stats.json` |
| One saved game | Resume a battle left mid-game | `foldfleet-saved-game.json` |

No name, email, location, contacts, photos, device identifier, or gameplay
data ever leaves the device in v1.

### Corrupt / missing data

If a saved file is missing or corrupt, the app starts with empty stats /
history instead of crashing. No data is repaired by sending anything anywhere.

### Future phases

If online multiplayer is added later, that phase will require a separate
privacy review before implementation: what account / matchmaking data is
needed, where it is hosted, how long it is kept, and the App Store privacy
nutrition labels that follow. No online feature will be added silently.

### App Store privacy labels (v1, to declare)

- Data collected: **None**
- Data linked to the user: **None**
- Tracking: **No**
