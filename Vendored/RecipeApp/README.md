# Recipe App for iPhone and Mac

Working title; the name is still open. The Xcode project and target are `Geist2`.

The project uses SwiftUI and has one app target for macOS 14 or later and iOS 17 or later. It has no third-party dependencies.

## Run on Mac

Open `Geist2.xcodeproj` in Xcode, choose **My Mac**, and press **Run**.

## Run on your iPhone

1. Open `Geist2.xcodeproj`.
2. In **Xcode → Settings → Apple Accounts**, sign in with your Apple Account if needed.
3. Select the **Geist2** target. In **Signing & Capabilities**, leave **Automatically manage signing** on and choose your team. If Xcode says the bundle identifier is in use, enter a unique one.
4. Connect your iPhone to the Mac. Trust the Mac when asked and enable **Developer Mode** on the iPhone if Xcode prompts you. Select your iPhone as the run destination and press **Run**.

[Apple’s physical-device testing guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

## Back up and restore

Open the **Cookbook actions** menu and choose **Download backup** to save the cookbook and grocery list as a JSON file, or **Restore backup** to replace them from one. AirDrop or iCloud Drive can move the file between devices. Cookbooks are stored separately on each device.

## Test Reminders

Open **Groceries → Connect to Reminders**, grant access, choose your Groceries list, and send unchecked items. Each export adds those items to the selected list. Use a temporary Reminders list if you want to test without changing your everyday list.

For scanning, use **Scan photo** and select a photo from Photos or an image file. Review the detected text and the ingredient list before saving. Website import supports pages that embed structured recipe data. Paste the recipe text when a site blocks import or omits that data.

## Share a recipe

Open a recipe and tap **Share recipe**. **Share as text** sends the title, category, time, ingredients, directions, and source through your system share sheet. **Share recipe file** attaches a JSON file a Recipe app user can save and open using **Cookbook actions → Import shared recipe**. Review it and tap **Save** to add it to your cookbook. Sharing omits personal notes and ratings.

## Change the appearance

Open **Cookbook actions → Appearance**. Choose **Simple** for a compact layout or **Cookbook** for the warm cookbook colors, food photography, and recipe covers. Recipe app remembers your choice on each device.

**Import link** tries the in-app browser automatically if direct import fails. If the browser finds a recipe, it opens the review screen. To browse and choose when to import, use **Open in browser → Import this page**.

During import or editing, select multiple **Categories**, or use **Add category** to make your own. In **Recipe photos**, add images from Photos, files, or URLs and use **Make cover** to pick the cookbook cover. When a new recipe matches a saved title or link, you can merge it or save a separate copy. For two saved matches, open either recipe, choose **Edit**, then **Merge with duplicate**.
