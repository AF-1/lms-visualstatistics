Visual Statistics
====
![Min. LMS Version](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fraw.githubusercontent.com%2FAF-1%2Fsobras%2Fmain%2Frepos%2Flms%2Fpublic.xml&cacheSeconds=172800&query=%2F%2F*%5Blocal-name()%3D'plugin'%20and%20%40name%3D'VisualStatistics'%5D%2F%40minTarget&prefix=v&label=Min.%20LMS%20Version%20Required&color=darkgreen)<br>

<img src="screenshots/vs_icon.png" align="right" width="90px">With **Visual Statistics**[^1] you can display statistics of your LMS music library using all kinds of charts. Hovering over segments, bars or data points will display more information.<br>

If you're interested in lists with tracks, albums or artists sorted by statistics for a specific artist, album, genre, year/decade or playlist, have a look at the [**Context Stats**](https://github.com/AF-1/#-context-stats) plugin.<br clear="right">

> [!TIP]
> The user interface and menus are here: `Home Menu > Extras > Visual Statistics`<br>


While the charts scale down, please note that this plugin was designed for wide/big screens.
<br><br>
If you have the [**Alternative Play Count**](https://github.com/AF-1/#-alternative-play-count) plugin installed, you will see some additional charts that use the data from this plugin.
<br><br>
[⬅️ **Back to the list of all plugins**](https://github.com/AF-1/)
<br><br>
**Use the** &nbsp; <img src="screenshots/menuicon.png" width="30"> &nbsp;**icon** (top right) to **jump directly to a specific section.**

<br><br>

## Features:
- Display statistics of your LMS music library using various types of charts.
- Save charts as images.
- 💡 The <b>bars</b> in many <i>bar charts</i> are <b>clickable</b> and will take you directly to the <b>browse menu</b> of the <i>artist, album, genre or year</i>.
- Limit the scope of charts to virtual libraries, decades and/or genres.
- Display (summary) library statistics in text form.
- Save the results for selected text statistics as playlists. Makes it easier to find those tracks, albums and artists.

<br><br>

## Screenshots[^2]
<img src="screenshots/vs.gif" width="100%">
<br><br>

## Installation

*Visual Statistics* is available from the LMS plugin library: `LMS > Settings > Manage Plugins`.<br>

If you want to test a new patch that hasn't made it into a release version yet, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).
<br><br><br><br>


## FAQ
<details><summary>»<b>The text stats show a line for <i>Possibly dead tracks in tracks_persistent table</i>. What does that mean and how do I get rid of them?</b>«</summary><br><p>
It just means that the tracks_persistent table where LMS stores values that survive rescans (normal play counts, ratings etc.) has entries for tracks that do not exists in the current library tables.<br>Save the result to a text file in the (parent folder of the) LMS preferences folder by clicking on the disk icon. Inspect the tracks. If you are certain that they're dead, create a backup copy of the LMS <i>persist.db</i> file and use the <a href="https://github.com/AF-1/#-potpourri"><b>PotPourri</b></a> plugin to purge them from the tracks_persistent table. Go to LMS Settings > Advanced > PotPourri.</p></details><br>
<br><br>


## Report a new issue

To report a new issue please file a GitHub [**issue report**](https://github.com/AF-1/lms-visualstatistics/issues/new/choose).
<br><br><br>

---

If this project was useful to you, you can star the repository using the <img src="screenshots/githubstar.png" width="20" height="20" alt="star" /> button in the top-right corner of this page.
<br><br><br>

[^1]: If you want localized strings in your language, please read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>.
[^2]: The screenshots might not correspond to the UI of the latest release in every detail.
