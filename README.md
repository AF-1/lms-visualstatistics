Visual Statistics
====

A plugin for [Logitech Media Server](https://github.com/Logitech/slimserver)<br>

<br>
Display statistics of your LMS music library using all kinds of charts. Hovering over segments, bars or data points will display more information. The <b>bars</b> in many <i>bar charts</i> are <b>clickable</b> and will take you directly to the <b>browse menu</b> of the <i>artist, album, genre or year</i>.<br>

Go to *Home Menu* > *Extras* > *Visual Statistics*
<br><br>
While the charts scale down, please note that this plugin was designed for wide/big screens.
<br><br>
If you have the [**Alternative Play Count**](https://github.com/AF-1/lms-alternativeplaycount) plugin installed, you will see some additional charts that use the data from this plugin.
<br><br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br><br>


## Installation

You should be able to install *Visual Statistics* from *LMS* > *Settings* > *Plugins*.<br>

If you want to test a new patch that hasn't made it into a release version yet or you need to install a previous version, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).

*Previously released* versions are available here for a *limited* time after the release of a new version. The official LMS plugins page is updated about twice a day so it usually takes a couple of hours before new released versions are listed.
<br><br><br><br>


## Translation
The [**strings.txt**](https://github.com/AF-1/lms-visualstatistics/blob/main/VisualStatistics/strings.txt) file contains all localizable strings. Once you're done **testing** the plugin with your translated strings (using the LMS *default* skin and *Material* skin) just create a pull request on GitHub.<br>
* Please try not to use the [**single**](https://www.fileformat.info/info/unicode/char/27/index.htm) quote character (apostrophe) or the [**double**](https://www.fileformat.info/info/unicode/char/0022/index.htm) quote character (quotation mark) in your translated strings. They could cause problems. You can use the [*right single quotation mark*](https://www.fileformat.info/info/unicode/char/2019/index.htm) or the [*double quotation mark*](https://www.fileformat.info/info/unicode/char/201d/index.htm) instead. And if possible, avoid (special) characters that are used as [**metacharacters**](https://en.wikipedia.org/wiki/Metacharacter) in programming languages (Perl), regex or SQLite.
* It's probably not a bad idea to keep the translated strings roughly as long as the original ones.<br>
* Please leave *(multiple) blank lines* (used to visually delineate different parts) as they are.
<br><br><br><br>


## Bug reports

If you're **reporting a bug** please **include relevant server log entries and the version number of LMS, Perl and your OS**. You'll find all of that on the  *LMS* > *Settings* > *Information* page.

Please post bug reports only [**here**](https://forums.slimdevices.com/showthread.php?114967-Announce-Visual-Statistics).
