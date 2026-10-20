# Public support and privacy pages

The static website source is in `site/`. It contains the public home, support and privacy pages, a shared stylesheet and a copy of the app icon. The approved public contact address is `mail@ephemeralimage.com`. Do not insert private Mail account inventories, email reports, signing settings or screenshots containing personal information.

Public URLs:

- Home: `https://keithholt.github.io/Mail-Filter/`
- App Store Support URL: `https://keithholt.github.io/Mail-Filter/support.html`
- App Store Privacy Policy URL: `https://keithholt.github.io/Mail-Filter/privacy.html`

Build 18 adds **Privacy Policy** and **Support** links at the top of the app's **Setup & help** page. They open these published pages in the default browser. The same URLs must be entered in App Store Connect's Privacy Policy URL and Support URL fields. Rebuild and upload the app when changing an embedded destination; editing website content alone does not require an app rebuild.

In the repository's **Settings → Pages**, select **GitHub Actions** as the publishing source. `.github/workflows/pages.yml` deploys only `site/` when its files or the workflow change on `main`. It can also be run manually. No app build, installer, engineering documents or private configuration is deployed by this workflow.

Edit the HTML/CSS directly. Preview with `python3 -m http.server 8765 --bind 127.0.0.1 --directory site`, then open `http://127.0.0.1:8765`. Check the pages at desktop and narrow widths, internal links, mail links and effective date before pushing. Keep the privacy policy consistent with actual storage, diagnostics, exports and the publisher's support process. A privacy-page update does not update an already signed app bundle.

The site has no added JavaScript, external fonts, analytics or advertising. GitHub Pages performs its own security logging, as disclosed on the privacy page. GitHub does not provide a receiving mailbox for the contact address; manage that address through its email provider.
