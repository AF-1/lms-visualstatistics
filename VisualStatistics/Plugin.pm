#
# Visual Statistics
#
# (c) 2021 AF
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::VisualStatistics::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Schema;
use JSON::XS;
use Time::HiRes qw(time);
use POSIX qw(strftime);

use constant LIST_URL => 'plugins/VisualStatistics/html/list.html';
use constant JSON_URL => 'plugins/VisualStatistics/getdata.html';

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.visualstatistics',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_VISUALSTATISTICS',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.visualstatistics');
my %ignoreCommonWords;
my $rowLimit = 50;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (main::WEBUI) {
		require Plugins::VisualStatistics::Settings;
		Plugins::VisualStatistics::Settings->new();
	}
	initPrefs();
	Slim::Web::Pages->addPageFunction(LIST_URL, \&handleWeb);
	Slim::Web::Pages->addPageFunction(JSON_URL, \&handleJSON);
	Slim::Web::Pages->addPageLinks('plugins', {'PLUGIN_VISUALSTATISTICS' => LIST_URL});

	Slim::Control::Request::addDispatch(['visualstatistics', 'savetopl', '_pltype'], [0, 1, 1, \&saveResultsToPL]);
}

sub initPrefs {
	$prefs->init({
		displayapcdupes => 1,
		minartisttracks => 3,
		minalbumtracks => 3,
		clickablebars => 1,
		savetoploverwrite => 1,
		savetoplmaxtracks => 3000,
	});
	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	if (!$apc_enabled && $prefs->get('displayapcdupes') == 2) {
		$prefs->set('displayapcdupes', 1);
	}
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 500, 'high' => 5000}, 'savetoplmaxtracks');
	$prefs->set('selectedvirtuallibrary', '');
	$prefs->set('status_savingtopl', 0);
	%ignoreCommonWords = map {
		$_ => 1
	} ("able", "about", "above", "acoustic", "act", "adagio", "after", "again", "against", "ago", "ain", "air", "akt", "album", "all", "allegretto", "allegro", "alone", "also", "alt", "alternate", "always", "among", "and", "andante", "another", "any", "are", "aria", "around", "atto", "autre", "away", "baby", "back", "bad", "beat", "because", "been", "before", "behind", "believe", "better", "big", "black", "blue", "bonus", "boy", "bring", "but", "bwv", "call", "can", "cause", "came", "chanson", "che", "chorus", "club", "come", "comes", "comme", "con", "concerto", "cosa", "could", "couldn", "dans", "das", "day", "days", "deezer", "dein", "del", "demo", "den", "der", "des", "did", "didn", "die", "does", "doesn", "don", "done", "down", "dub", "dur", "each", "edit", "ein", "either", "else", "end", "est", "even", "ever", "every", "everybody", "everything", "extended", "feat", "featuring", "feel", "find", "first", "flat", "for", "from", "fur", "get", "girl", "give", "going", "gone", "gonna", "good", "got", "gotta", "had", "hard", "has", "have", "hear", "heart", "her", "here", "hey", "him", "his", "hit", "hold", "home", "how", "ich", "iii", "inside", "instrumental", "interlude", "into", "intro", "isn", "ist", "just", "keep", "know", "las", "last", "leave", "left", "les", "let", "life", "like", "little", "live", "long", "look", "los", "love", "made", "major", "make", "man", "master", "may", "medley", "mein", "meu", "might", "mind", "mine", "minor", "miss", "mix", "moderato", "moi", "moll", "molto", "mon", "mono", "more", "most", "move", "much", "music", "must", "myself", "name", "nao", "near", "need", "never", "new", "nicht", "nobody", "non", "not", "nothing", "now", "off", "old", "once", "one", "only", "ooh", "orchestra", "original", "other", "ouh", "our", "ours", "out", "over", "own", "part", "pas", "people", "piano", "place", "play", "please", "plus", "por", "pour", "prelude", "presto", "put", "quartet", "que", "qui", "quite", "radio", "rather", "real", "really", "recitativo", "recorded", "remix", "right", "rock", "roll", "run", "said", "same", "sao", "say", "scene", "see", "seem", "session", "she", "should", "shouldn", "side", "single", "skit", "solo", "some", "something", "somos", "son", "sonata", "song", "sous", "spotify", "start", "stay", "stereo", "still", "stop", "street", "such", "suite", "symphony", "szene", "take", "talk", "teil", "tel", "tell", "tempo", "than", "that", "the", "their", "them", "then", "there", "these", "they", "thing", "things", "think", "this", "those", "though", "thought", "three", "through", "thus", "till", "time", "titel", "together", "told", "tonight", "too", "track", "trio", "true", "try", "turn", "two", "una", "und", "under", "une", "until", "use", "version", "very", "vivace", "vocal", "walk", "wanna", "want", "was", "way", "well", "went", "were", "what", "when", "where", "whether", "which", "while", "who", "whose", "why", "will", "with", "without", "woman", "won", "woo", "world", "would", "wrong", "yeah", "yes", "yet", "you", "your");
}

sub handleWeb {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	$prefs->set('genrefilterid', '');
	$prefs->set('decadefilterval', '');
	$prefs->set('selectedvirtuallibrary', '');
	$params->{'vlselect'} = $prefs->get('selectedvirtuallibrary');

	my $host = $params->{host} || (Slim::Utils::Network::serverAddr() . ':' . preferences('server')->get('httpport'));
	$params->{'squeezebox_server_jsondatareq'} = 'http://' . $host . '/jsonrpc.js';

	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks,tracks_persistent where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL) || 0;
	$params->{'ratedtrackcount'} = $ratedTrackCount;

	$params->{'virtuallibraries'} = getVirtualLibraries();
	$params->{'librarygenres'} = getGenres();

	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	$params->{'apcenabled'} = 1 if $apc_enabled;
	$params->{'displayapcdupes'} = $prefs->get('displayapcdupes');
	$params->{'clickablebars'} = $prefs->get('clickablebars') || 'noclick';
	$params->{'usefullscreen'} = $prefs->get('usefullscreen') ? 1 : 0;
	$params->{'txtrefreshbtn'} = $prefs->get('txtrefreshbtn');

	if (Slim::Utils::Versions->compareVersions($::VERSION, '9.0') >= 0) {
		my $workTrackCountSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.work is not null";
		my $workTrackCount = quickSQLcount($workTrackCountSQL) || 0;
		$params->{'lmsminversion_works'} = 1 if $workTrackCount;

		my $ratedWorkTrackCountSQL = "select count(distinct tracks.id) from tracks,tracks_persistent where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks.work is not null and tracks_persistent.rating > 0";
		my $ratedWorkTrackCount = quickSQLcount($ratedWorkTrackCountSQL) || 0;
		$params->{'ratedworktrackcount'} = $ratedWorkTrackCount;
	}

	return Slim::Web::HTTP::filltemplatefile($params->{'path'}, $params);
}

sub handleJSON {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	my $response = {error => 'Invalid or missing query type'};
	my $querytype = $params->{content};
	main::DEBUGLOG && $log->is_debug && $log->debug('query type = '.Data::Dump::dump($querytype));

	my $started = time();

	if ($querytype) {
		$response = {
			error => 0,
			msg => $querytype
		};
		if ($querytype eq 'decadelist') {
			$response = {
				results => getDecades(),
			};
		} elsif ($querytype eq 'genrelist') {
			$response = {
				results => getGenres(),
			};
		} else {
			$response = {
				results => eval("$querytype()")
			};
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('JSON response = '.Data::Dump::dump($response));
	main::INFOLOG && $log->is_info && $log->info('exec time for query "'.$querytype.'" = '.(time()-$started).' seconds.') if $querytype;
	my $content = $params->{callback} ? $params->{callback}.'('.encode_json($response).')' : encode_json($response);
	$httpResponse->header('Content-Length' => length($content));

	return \$content;
}

## ---- library stats text ---- ##

sub getDataLibStatsText {
	my @result = ();
	my $selectedVL = $prefs->get('selectedvirtuallibrary');

	my $VLname = Slim::Music::VirtualLibraries->getNameForId($selectedVL) || string("PLUGIN_VISUALSTATISTICS_VL_COMPLETELIB_NAME");
	push (@result, {'name' => 'vlheadername', 'value' => Slim::Utils::Unicode::utf8decode($VLname, 'utf8')});

	# number of tracks
	my $trackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$trackCountSQL .= " where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCount = quickSQLcount($trackCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKS").':', 'value' => $trackCount});

	# number of local tracks/files
	my $trackCountLocalSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountLocalSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$trackCountLocalSQL .= " where tracks.audio = 1 and tracks.remote = 0 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountLocal = quickSQLcount($trackCountLocalSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKSLOCAL").':', 'value' => $trackCountLocal});

	# number of remote tracks
	my $trackCountRemoteSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountRemoteSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$trackCountRemoteSQL .= " where tracks.audio =1 and tracks.remote = 1 and tracks.extid is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountRemote = quickSQLcount($trackCountRemoteSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKSREMOTE").':', 'value' => $trackCountRemote});

	# total playing time
	my $totalTimeSQL = "select sum(secs) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$totalTimeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$totalTimeSQL .=" where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $totalTime = prettifyTime(quickSQLcount($totalTimeSQL));
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALPLAYINGTIME").':', 'value' => $totalTime});

	# total library size
	my $totalLibrarySizeSQL = "select round((sum(filesize)/1024/1024/1024),2)||' GB' from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$totalLibrarySizeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$totalLibrarySizeSQL .= " where tracks.audio = 1 and tracks.remote = 0 and tracks.filesize is not null";
	my $totalLibrarySize = quickSQLcount($totalLibrarySizeSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALLIBSIZE").':', 'value' => $totalLibrarySize});

	# library age
	my $libraryAgeinSecsSQL = "select (strftime('%s', 'now', 'localtime') - min(tracks_persistent.added)) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$libraryAgeinSecsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$libraryAgeinSecsSQL .= " join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.audio = 1";
	my $libraryAge = prettifyTime(quickSQLcount($libraryAgeinSecsSQL));
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALIBAGE").':', 'value' => $libraryAge});

	# number of artists (artists, album artists + track artists)
	my $artistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$artistCountSQL .= " join library_contributor on contributor_track.contributor = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$artistCountSQL .= " where contributor_track.role in (1,5,6)";
	my $artistCount = quickSQLcount($artistCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS").':', 'value' => $artistCount});

	# number of album artists
	my $albumArtistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$albumArtistCountSQL .= " join library_contributor on contributor_track.contributor = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$albumArtistCountSQL .= " where contributor_track.role = 5";
	my $albumArtistCount = quickSQLcount($albumArtistCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AARTISTS").':', 'value' => $albumArtistCount});

	# number of composers
	my $composerCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$composerCountSQL .= " join library_contributor on contributor_track.contributor = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$composerCountSQL .= " where contributor_track.role = 2";
	my $composerCount = quickSQLcount($composerCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_COMPOSERS").':', 'value' => $composerCount});

	# number of conductors
	my $conductorCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$conductorCountSQL .= " join library_contributor on contributor_track.contributor = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$conductorCountSQL .= " where contributor_track.role = 3";
	my $conductorCount = quickSQLcount($conductorCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_CONDUCTORS").':', 'value' => $conductorCount}) if $conductorCount > 0;

	# number of bands
	my $bandCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$bandCountSQL .= " join library_contributor on contributor_track.contributor = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$bandCountSQL .= " where contributor_track.role = 4";
	my $bandCount = quickSQLcount($bandCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_BANDS").':', 'value' => $bandCount}) if $bandCount > 0;

	# number of artists played
	my $artistsPlayedSQL = "select count(distinct contributor_track.contributor) from contributor_track
		join tracks on
			tracks.id = contributor_track.track";
	if ($selectedVL && $selectedVL ne '') {
		$artistsPlayedSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$artistsPlayedSQL .= " join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5 and tracks_persistent.playcount > 0
		where
			tracks.audio = 1
			and contributor_track.role in (1,5,6)";
	my $artistsPlayedFloat = quickSQLcount($artistsPlayedSQL)/$artistCount * 100;
	my $artistsPlayedPercentage = sprintf("%.1f", $artistsPlayedFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTSPLAYED").':', 'value' => $artistsPlayedPercentage});

	# number of albums
	my $albumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsCountSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsCountSQL .= " where tracks.audio = 1";
	my $albumsCount = quickSQLcount($albumsCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS").':', 'value' => $albumsCount});

	if (Slim::Utils::Versions->compareVersions($::VERSION, '9.0') >= 0) {
		# number of works
		my $worksCountSQL = "select count(distinct works.id) from works join tracks on tracks.work = works.id";
		if ($selectedVL && $selectedVL ne '') {
			$worksCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$worksCountSQL .= " where tracks.audio = 1";
		my $worksCount = quickSQLcount($worksCountSQL);
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_WORKS").':', 'value' => $worksCount});

		# number of works with < 1 performance
		my $worksMultiplePerformancesCountSQL = "select works.id, (select count(distinct album||work||coalesce(performance,1)) from tracks where tracks.work = works.id) as noofperformances from works join tracks on tracks.work = works.id";
		if ($selectedVL && $selectedVL ne '') {
			$worksMultiplePerformancesCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$worksMultiplePerformancesCountSQL .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id having noofperformances > 1";
		my $dbh = Slim::Schema->dbh;
		my $sth = $dbh->prepare($worksMultiplePerformancesCountSQL);
		$sth->execute();
		my $worksMultiplePerformancesArr = $sth->fetchall_arrayref();
		$sth->finish();
		if (scalar @{$worksMultiplePerformancesArr} > 0) {
			my $worksMultiplePerformancesCountPercentage = sprintf("%.1f", (scalar @{$worksMultiplePerformancesArr}/$worksCount * 100)).'%';
			push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_WORKS_MULTIPLE_PERFORMANCES").':', 'value' => $worksMultiplePerformancesCountPercentage});
		}
	}

	# number of compilations
	my $compilationsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$compilationsCountSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$compilationsCountSQL .= " where tracks.audio = 1 and albums.compilation = 1";
	my $compilationsCountFloat = quickSQLcount($compilationsCountSQL)/$albumsCount * 100;
	my $compilationsCountPercentage = sprintf("%.1f", $compilationsCountFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_COMPIS").':', 'value' => $compilationsCountPercentage});

	# number of artist albums
	my $artistAlbumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$artistAlbumsCountSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$artistAlbumsCountSQL .= " where tracks.audio = 1 and (albums.compilation is null or albums.compilation = 0)";
	my $artistAlbumsCount = quickSQLcount($artistAlbumsCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AALBUMS").':', 'value' => $artistAlbumsCount});

	# number of albums played
	my $albumsPlayedSQL = "select count(distinct albums.id) from albums
		join tracks on
			tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsPlayedSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
		$albumsPlayedSQL .= " join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.audio = 1
			and tracks_persistent.playcount > 0";
	my $albumsPlayedFloat = quickSQLcount($albumsPlayedSQL)/$albumsCount * 100;
	my $albumsPlayedPercentage = sprintf("%.1f", $albumsPlayedFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSPLAYED").':', 'value' => $albumsPlayedPercentage});

	# number of albums without artwork
	my $albumsNoArtworkSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsNoArtworkSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsNoArtworkSQL .= " where tracks.audio = 1 and albums.artwork is null";
	my $albumsNoArtwork = quickSQLcount($albumsNoArtworkSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSNOARTWORK").':', 'value' => $albumsNoArtwork, 'savetopl' => 'albumswithoutartwork'}) if $albumsNoArtwork > 0;

	# number of albums without year
	my $albumsNoYearSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsNoYearSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsNoYearSQL .= " where tracks.audio = 1 and ifnull(albums.year, 0) = 0";
	my $albumsNoYear = quickSQLcount($albumsNoYearSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSNOYEAR").':', 'value' => $albumsNoYear, 'savetopl' => 'albumswithoutyear'}) if $albumsNoYear > 0;

	# number of albums with album replay gain
	my $albumsWithReplayGainSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsWithReplayGainSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsWithReplayGainSQL .= " where tracks.audio = 1 and albums.replay_gain is not null";
	my $albumsWithReplayGain = quickSQLcount($albumsWithReplayGainSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSWITHREPLAYGAIN").':', 'value' => $albumsWithReplayGain, 'savetopl' => 'albumswithreplaygain'}) if $albumsWithReplayGain > 0;

	# number of albums with album replay peak
	my $albumsWithReplayPeakSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsWithReplayPeakSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsWithReplayPeakSQL .= " where tracks.audio = 1 and albums.replay_peak is not null";
	my $albumsWithReplayPeak = quickSQLcount($albumsWithReplayPeakSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSWITHREPLAYPEAK").':', 'value' => $albumsWithReplayPeak, 'savetopl' => 'albumswithreplaypeak'}) if $albumsWithReplayPeak > 0;

	# number of genres
	my $genreCountSQL = "select count(distinct genre_track.genre) from genre_track";
	if ($selectedVL && $selectedVL ne '') {
		$genreCountSQL .= " join library_genre on genre_track.genre = library_genre.genre and library_genre.library = '$selectedVL'";
	}
	my $genreCount = quickSQLcount($genreCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_GENRES").':', 'value' => $genreCount});

	# number of lossless tracks
	my $losslessTrackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$losslessTrackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$losslessTrackCountSQL .= " where tracks.audio = 1 and tracks.lossless = 1";
	my $losslessTrackCountFloat = quickSQLcount($losslessTrackCountSQL)/$trackCount * 100;
	my $losslessTrackCountPercentage = sprintf("%.1f", $losslessTrackCountFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_LOSSLESS").':', 'value' => $losslessTrackCountPercentage});

	# number of rated tracks
	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks, tracks_persistent";
	if ($selectedVL && $selectedVL ne '') {
		$ratedTrackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$ratedTrackCountSQL .= " where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL);
	my $ratedTrackCountPercentage = sprintf("%.1f", ($ratedTrackCount/$trackCount * 100)).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_RATEDTRACKS").':', 'value' => $ratedTrackCountPercentage});

	# number of tracks played at least once
	my $songsPlayedOnceSQL = "select count(distinct tracks.id) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5";
	if ($selectedVL && $selectedVL ne '') {
		$songsPlayedOnceSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$songsPlayedOnceSQL .= " where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedOnceFloat = quickSQLcount($songsPlayedOnceSQL)/$trackCount * 100;
	my $songsPlayedOncePercentage = sprintf("%.1f", $songsPlayedOnceFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSPLAYED").':', 'value' => $songsPlayedOncePercentage});

	# total play count
	my $songsPlayedTotalSQL = "select sum(tracks_persistent.playcount) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5";
	if ($selectedVL && $selectedVL ne '') {
		$songsPlayedTotalSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$songsPlayedTotalSQL .= " where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedTotal = quickSQLcount($songsPlayedTotalSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSPLAYCOUNTTOTAL").':', 'value' => $songsPlayedTotal});

	# average track length
	my $avgTrackLengthSQL = "select strftime('%M:%S', avg(secs)/86400.0) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgTrackLengthSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$avgTrackLengthSQL .= " where tracks.audio = 1";
	my $avgTrackLength = quickSQLcount($avgTrackLengthSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSAVGLENGTH").':', 'value' => $avgTrackLength.' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMINS")});

	# average bit rate
	my $avgBitrateSQL = "select round((avg(bitrate)/10000)*10) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgBitrateSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$avgBitrateSQL .= " where tracks.audio = 1 and tracks.bitrate is not null";
	my $avgBitrate = quickSQLcount($avgBitrateSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AVGBITRATE").':', 'value' => $avgBitrate.' kbps'});

	# average file size
	my$avgFileSizeSQL = "select round((avg(filesize)/(1024*1024)), 2)||' MB' from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgFileSizeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$avgFileSizeSQL .= " where tracks.audio = 1 and tracks.remote=0 and tracks.filesize is not null";
	my $avgFileSize = quickSQLcount($avgFileSizeSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AVGFILESIZE").':', 'value' => $avgFileSize});

	# number of tracks with lyrics
	my $tracksWithLyricsSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksWithLyricsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksWithLyricsSQL .= " where tracks.audio = 1 and tracks.lyrics is not null";
	my $tracksWithLyricsFloat = quickSQLcount($tracksWithLyricsSQL)/$trackCount * 100;
	my $tracksWithLyricsPercentage = sprintf("%.1f", $tracksWithLyricsFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSWITHLYRICS").':', 'value' => $tracksWithLyricsPercentage});

	# number of tracks without year
	my $tracksNoYearSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksNoYearSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksNoYearSQL .= " where tracks.audio = 1 and tracks.filesize is not null and ifnull(tracks.year, 0) = 0";
	my $tracksNoYear = quickSQLcount($tracksNoYearSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSNOYEAR").':', 'value' => $tracksNoYear, 'savetopl' => 'trackswithoutyear'}) if $tracksNoYear > 0;

	# number of tracks without replay gain
	my $tracksNoReplayGainSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksNoReplayGainSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksNoReplayGainSQL .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_gain is null";
	my $tracksNoReplayGain = quickSQLcount($tracksNoReplayGainSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSNOREPLAYGAIN").':', 'value' => $tracksNoReplayGain, 'savetopl' => 'trackswithoutreplaygain'}) if $tracksNoReplayGain > 0;

	# number of tracks with replay peak
	my $tracksWithReplayPeakSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksWithReplayPeakSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksWithReplayPeakSQL .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_peak is not null";
	my $tracksWithReplayPeak = quickSQLcount($tracksWithReplayPeakSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSWITHREPLAYPEAK").':', 'value' => $tracksWithReplayPeak, 'savetopl' => 'trackswithreplaypeak'}) if $tracksWithReplayPeak > 0;

	# number of tracks for each mp3 tag version
	my $mp3tagversionsSQL = "select tracks.tagversion as thistagversion, count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$mp3tagversionsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$mp3tagversionsSQL .= " where tracks.audio=1 and tracks.content_type = 'mp3' and tracks.tagversion is not null group by tracks.tagversion";
	my $mp3tagversions = executeSQLstatement($mp3tagversionsSQL);
	my @sortedmp3tagversions = sort { $a->{'xAxis'} cmp $b->{'xAxis'} } @{$mp3tagversions};
	if (scalar(@sortedmp3tagversions) > 0) {
		foreach my $thismp3tagversion (@sortedmp3tagversions) {
			push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_MP3TRACKSTAGS").' '.$thismp3tagversion->{'xAxis'}.' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TAGS").':', 'value' => $thismp3tagversion->{'yAxis'}, 'savetopl' => $thismp3tagversion->{'xAxis'}});
		}
	}

	# number of tracks with track musicbrainz id
	my $tracksMusicbrainzIdSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksMusicbrainzIdSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksMusicbrainzIdSQL .= " where tracks.audio = 1 and tracks.musicbrainz_id is not null";
	my $tracksMusicbrainzId = quickSQLcount($tracksMusicbrainzIdSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_MUSICBRAINZID").':', 'value' => $tracksMusicbrainzId, 'savetopl' => 'trackswithmusicbrainzid'}) if $tracksMusicbrainzId > 0;

	# number of tracks with identical musicbrainz ids in the LMS tracks table
	if ($tracksMusicbrainzId > 0) {
		my $tracksMusicbrainzIdDupeSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$tracksMusicbrainzIdDupeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$tracksMusicbrainzIdDupeSQL .= " where tracks.musicbrainz_id is not null group by tracks.musicbrainz_id having count(tracks.musicbrainz_id) > 1)";
		my $tracksMusicbrainzIDdupeCount = quickSQLcount($tracksMusicbrainzIdDupeSQL);
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_MUSICBRAINZID_DUPES").':', 'value' => $tracksMusicbrainzIDdupeCount, 'savetopl' => 'trackswithidenticalmusicbrainzid'}) if $tracksMusicbrainzIDdupeCount > 0;
	}

	# number of artists with artist musicbrainz id
	my $artistsMusicbrainzIdSQL = "select count(distinct contributors.id) from contributors";
	if ($selectedVL && $selectedVL ne '') {
		$artistsMusicbrainzIdSQL .= " join library_contributor on contributors.id = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$artistsMusicbrainzIdSQL .= " where contributors.musicbrainz_id is not null";
	my $artistsMusicbrainzId = quickSQLcount($artistsMusicbrainzIdSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_MUSICBRAINZID").':', 'value' => $artistsMusicbrainzId, 'savetopl' => 'artistswithmusicbrainzid'}) if $artistsMusicbrainzId > 0;

	# Various Artists has musicbrainz id ?
	my $VAid = Slim::Schema->variousArtistsObject->id;
	my $VAMusicbrainzIdSQL = "select count(distinct contributors.id) from contributors where contributors.musicbrainz_id is not null and contributors.id = $VAid";
	my $VAMusicbrainzId = quickSQLcount($VAMusicbrainzIdSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_MUSICBRAINZID_VA").':', 'value' => string('YES')}) if $VAMusicbrainzId > 0;

	# number of artists with identical musicbrainz ids in the LMS contributors table
	if ($artistsMusicbrainzId > 0) {
		my $artistsMusicbrainzIdDupeSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from contributors";
		if ($selectedVL && $selectedVL ne '') {
			$artistsMusicbrainzIdDupeSQL .= " join library_contributor on contributors.id = library_contributor.contributor and library_contributor.library = '$selectedVL'";
		}
		$artistsMusicbrainzIdDupeSQL .= " where contributors.musicbrainz_id is not null group by contributors.musicbrainz_id having count(contributors.musicbrainz_id) > 1)";
		my $artistsMusicbrainzIDdupeCount = quickSQLcount($artistsMusicbrainzIdDupeSQL);
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_MUSICBRAINZID_DUPES").':', 'value' => $artistsMusicbrainzIDdupeCount, 'savetopl' => 'artistswithidenticalmusicbrainzid'}) if $artistsMusicbrainzIDdupeCount > 0;
	}

	# number of albums with album musicbrainz id
	my $albumsMusicbrainzIdSQL = "select count(distinct albums.id) from albums";
	if ($selectedVL && $selectedVL ne '') {
		$albumsMusicbrainzIdSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsMusicbrainzIdSQL .= " where albums.musicbrainz_id is not null";
	my $albumsMusicbrainzId = quickSQLcount($albumsMusicbrainzIdSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS_MUSICBRAINZID").':', 'value' => $albumsMusicbrainzId, 'savetopl' => 'albumswithmusicbrainzid'}) if $albumsMusicbrainzId > 0;

	# number of albums with identical musicbrainz ids in the LMS albums table
	if ($albumsMusicbrainzId > 0) {
		my $albumsMusicbrainzIdDupeSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from albums";
		if ($selectedVL && $selectedVL ne '') {
		$albumsMusicbrainzIdDupeSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
		}
		$albumsMusicbrainzIdDupeSQL .= " where albums.musicbrainz_id is not null group by albums.musicbrainz_id having count(albums.musicbrainz_id) > 1)";
		my $albumsMusicbrainzIDdupeCount = quickSQLcount($albumsMusicbrainzIdDupeSQL);
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS_MUSICBRAINZID_DUPES").':', 'value' => $albumsMusicbrainzIDdupeCount, 'savetopl' => 'albumswithidenticalmusicbrainzid'}) if $albumsMusicbrainzIDdupeCount > 0;
	}

	# number of contributors without tracks
	my $artistsWithoutTracksSQL ="select ifnull(sum(cnt),0) from (select count(*) as cnt from contributors";
	if ($selectedVL && $selectedVL ne '') {
		$artistsWithoutTracksSQL .= " join library_contributor on contributors.id = library_contributor.contributor and library_contributor.library = '$selectedVL'";
	}
	$artistsWithoutTracksSQL .= " left join contributor_track on contributor_track.contributor = contributors.id left join tracks on contributor_track.track = tracks.id where tracks.id is null)";
	my $artistsWithoutTracks = quickSQLcount($artistsWithoutTracksSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_NOTRACKS").':', 'value' => $artistsWithoutTracks}) if $artistsWithoutTracks > 0;

	# number of albums without tracks
	my $albumsWithoutTracksSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from albums";
	if ($selectedVL && $selectedVL ne '') {
		$albumsWithoutTracksSQL .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
	}
	$albumsWithoutTracksSQL .= " left join tracks on albums.id = tracks.album where tracks.id is null)";
	my $albumsWithoutTracks = quickSQLcount($albumsWithoutTracksSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS_NOTRACKS").':', 'value' => $albumsWithoutTracks}) if $albumsWithoutTracks > 0;

	# number of genres without tracks
	my $genresWithoutTracksSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from genres";
	if ($selectedVL && $selectedVL ne '') {
		$genresWithoutTracksSQL .= " join library_genre on genre_track.genre = library_genre.genre and library_genre.library = '$selectedVL'";
	}
	$genresWithoutTracksSQL .= " left join genre_track on genre_track.genre = genres.id left join tracks on genre_track.track = tracks.id where tracks.id is null)";
	$albumsWithoutTracksSQL .= " left join tracks on albums.id = tracks.album where tracks.id is null)";
	my $genresWithoutTracks = quickSQLcount($genresWithoutTracksSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_GENRES_NOTRACKS").':', 'value' => $genresWithoutTracks}) if $genresWithoutTracks > 0;

	# number of years without tracks
	my $yearsWithoutTracksSQL = "select ifnull(sum(cnt),0) from (select count(*) as cnt from years left join tracks on years.id = tracks.year";
	if ($selectedVL && $selectedVL ne '') {
		$yearsWithoutTracksSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$yearsWithoutTracksSQL .= " where tracks.id is null)";
	my $yearsWithoutTracks = quickSQLcount($yearsWithoutTracksSQL);
	if ($yearsWithoutTracks > 0) {
		my $yearCount = quickSQLcount("select count(*) from years where years.id is not null");
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_YEARS_NOTRACKS").':', 'value' => $yearsWithoutTracks}) if $yearCount > 0;
	}

	# tracks with long urls (> 2048 characters)
	my $tracksWithLongUrlSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksWithLongUrlSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
	}
	$tracksWithLongUrlSQL .= " where tracks.audio = 1 and length(tracks.url) > 2048";
	my $tracksWithLongURL = quickSQLcount($tracksWithLongUrlSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_LONGURLS").':', 'value' => $tracksWithLongURL, 'savetopl' => 'trackswithlongurl'}) if $tracksWithLongURL > 0;

	# possibly dead tracks in tracks_persistent table
	my $deadTracksPersistentSQL = "select count(*) from tracks_persistent where urlmd5 not in (select urlmd5 from tracks where tracks.urlmd5 = tracks_persistent.urlmd5)";
	my $deadTracksPersistent = quickSQLcount($deadTracksPersistentSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_DEADTRACKSPERSISTENT").':', 'value' => $deadTracksPersistent}) if $deadTracksPersistent > 0;

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(\@result));
	return \@result;
}

sub saveResultsToPL {
	if ($prefs->get('status_savingtopl') == 1) {
		$log->warn('LMS is already saving the results to a playlist. Please wait for the process to finish.');
		return;
	}
	$prefs->set('status_savingtopl', 1);

	my $request = shift;
	my $params = $request->getParamsCopy();
	main::DEBUGLOG && $log->is_debug && $log->debug('params = '.Data::Dump::dump($params));
	my $playlistType = $params->{_pltype};
	return if !$playlistType;
	my $selectedVL = $prefs->get('selectedvirtuallibrary');

	## get sql, sort order and playlist name
	my $sqlstatement;
	my $sortOrder = 1;
	my $staticPLname = 'Visual Statistics - ';

	# albums without artwork
	if ($playlistType eq 'albumswithoutartwork') {
		$sqlstatement = "select tracks.id from albums join tracks on tracks.album = albums.id";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and albums.artwork is null group by albums.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSNOARTWORK');
	}

	# albums without year
	if ($playlistType eq 'albumswithoutyear') {
		$sqlstatement = "select tracks.id from albums join tracks on tracks.album = albums.id";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and ifnull(albums.year, 0) = 0 group by albums.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSNOYEAR');
	}

	# albums with album replay gain
	if ($playlistType eq 'albumswithreplaygain') {
		$sqlstatement = "select tracks.id from tracks join albums on tracks.album = albums.id";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and albums.replay_gain is not null group by albums.id";
		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSWITHREPLAYGAIN');
	}

	# albums with album replay peak
	if ($playlistType eq 'albumswithreplaypeak') {
		$sqlstatement = "select tracks.id from tracks join albums on tracks.album = albums.id";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and albums.replay_peak is not null group by albums.id";
		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSWITHREPLAYPEAK');
	}

	# tracks without year
	if ($playlistType eq 'trackswithoutyear') {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and ifnull(tracks.year, 0) = 0 group by tracks.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSNOYEAR');
	}

	# tracks without replay gain
	if ($playlistType eq 'trackswithoutreplaygain') {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_gain is null group by tracks.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSNOREPLAYGAIN');
	}

	# tracks with replay peak
	if ($playlistType eq 'trackswithreplaypeak') {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_peak is not null group by tracks.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSWITHREPLAYPEAK');
	}

	# tracks for mp3 tag version
	if (rindex($playlistType,'ID3v', 0) == 0) {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and tracks.content_type = 'mp3' and tracks.tagversion is \"$playlistType\" group by tracks.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_MP3TRACKSTAGS').' '.$playlistType.' '.string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TAGS');
	}

	# tracks with Musicbrainz ID
	if ($playlistType eq 'trackswithmusicbrainzid') {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and tracks.musicbrainz_id is not null group by tracks.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_MUSICBRAINZID');
	}

	# tracks with identical Musicbrainz IDs in the LMS tracks table
	if ($playlistType eq 'trackswithidenticalmusicbrainzid') {
		$sqlstatement = "select tracks.id from tracks where tracks.id in (select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and tracks.musicbrainz_id is not null and tracks.musicbrainz_id in (select othertracks.musicbrainz_id from tracks othertracks where othertracks.musicbrainz_id is not null group by othertracks.musicbrainz_id having count(othertracks.musicbrainz_id) > 1))";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_MUSICBRAINZID_DUPES');
	}

	# artists with Musicbrainz ID
	if ($playlistType eq 'artistswithmusicbrainzid') {
		$sqlstatement = "select tracks.id from tracks join contributor_track on contributor_track.track = tracks.id join contributors on contributors.id = contributor_track.contributor";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_contributor on contributors.id = library_contributor.contributor and library_contributor.library = '$selectedVL'";
		}
		$sqlstatement .= " where contributors.musicbrainz_id is not null group by contributors.id";

		$sortOrder = 2;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_MUSICBRAINZID');
	}

	# artists with identical Musicbrainz IDs
	if ($playlistType eq 'artistswithidenticalmusicbrainzid') {
		my $VAid = Slim::Schema->variousArtistsObject->id;
		$sqlstatement = "select tracks.id from tracks where tracks.id in (select tracks.id from tracks join contributor_track on contributor_track.track = tracks.id join contributors on contributors.id = contributor_track.contributor";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_contributor on contributors.id = library_contributor.contributor and library_contributor.library = '$selectedVL'";
		}
		$sqlstatement .= " where contributors.musicbrainz_id is not null and contributors.musicbrainz_id in (select othercontributors.musicbrainz_id from contributors othercontributors where othercontributors.musicbrainz_id is not null group by othercontributors.musicbrainz_id having count(othercontributors.musicbrainz_id) > 1) group by contributors.id)";

		$sortOrder = 2;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS_MUSICBRAINZID_DUPES');
	}

	# albums with Musicbrainz ID
	if ($playlistType eq 'albumswithmusicbrainzid') {
		$sqlstatement = "select tracks.id from tracks join albums on tracks.album = albums.id";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
		}
		$sqlstatement .= " where albums.musicbrainz_id is not null group by albums.id";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS_MUSICBRAINZID');
	}

	# albums with identical Musicbrainz IDs
	if ($playlistType eq 'albumswithidenticalmusicbrainzid') {
		$sqlstatement = "select tracks.id from tracks where tracks.id in (select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_album on library_album.album = albums.id and library_album.library = '$selectedVL'";
		}
		$sqlstatement .= " join albums on tracks.album = albums.id where albums.musicbrainz_id is not null and albums.musicbrainz_id in (select otheralbums.musicbrainz_id from albums otheralbums where otheralbums.musicbrainz_id is not null group by otheralbums.musicbrainz_id having count(otheralbums.musicbrainz_id) > 1) group by albums.id)";

		$sortOrder = 3;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS_MUSICBRAINZID_DUPES');
	}

	# tracks with long urls (> 2048 characters)
	if ($playlistType eq 'trackswithlongurl') {
		$sqlstatement = "select tracks.id from tracks";
		if ($selectedVL && $selectedVL ne '') {
			$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'";
		}
		$sqlstatement .= " where tracks.audio = 1 and length(tracks.url) > 2048 group by tracks.id";

		$sortOrder = 4;
		$staticPLname .= string('PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKS_LONGURLS');
	}

	my $staticPLmaxTrackLimit = $prefs->get('savetoplmaxtracks');
	main::DEBUGLOG && $log->is_debug && $log->debug("Creating static playlist with max. $staticPLmaxTrackLimit items for type: $playlistType");
	my $started = time();

	## get track ids
	my @trackIDs = ();
	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute() or do {
		$log->warn('sqlstatement = '.$sqlstatement);
		$sqlstatement = undef;
	};

	if (!$sqlstatement) {
		$log->warn("Problem with saving playlist for type $playlistType.");
		$prefs->set('status_savingtopl', 0);
		return;
	}

	my $trackID;
	$sth->bind_col(1,\$trackID);
	while ($sth->fetch()) {
		push (@trackIDs, $trackID);
	}
	$sth->finish();

	## limit results if necessary
	if (scalar(@trackIDs) > $staticPLmaxTrackLimit) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Limiting the number of saved playlist tracks to the specified limit ($staticPLmaxTrackLimit)");
		my $limitingExecStartTime = time();
		@trackIDs = @trackIDs[0..($staticPLmaxTrackLimit - 1)];
		main::DEBUGLOG && $log->is_debug && $log->debug('Limiting exec time: '.(time() - $limitingExecStartTime).' secs');
	}

	## Get tracks for ids
	my @allTracks;
	my $getTracksForIDsStartTime = time();
	foreach (@trackIDs) {
		push @allTracks, Slim::Schema->rs('Track')->single({'id' => $_});
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting track objects for track IDs took '.(time()-$getTracksForIDsStartTime). ' seconds');
	main::idleStreams();

	# Sort tracks?
	if (scalar(@allTracks) > 1 && $sortOrder > 1) {
		my $sortStartTime= time();
		if ($sortOrder == 2) {
			# sort order: artist > album > disc no. > track no.
			@allTracks = sort {lc($a->artist->namesort) cmp lc($b->artist->namesort) || lc($a->album->namesort) cmp lc($b->album->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @allTracks;
		} elsif ($sortOrder == 3) {
			# sort order: album > artist > disc no. > track no.
			@allTracks = sort {lc($a->album->namesort) cmp lc($b->album->namesort) || lc($a->artist->namesort) cmp lc($b->artist->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @allTracks;
		} elsif ($sortOrder == 4) {
			# sort order: album > disc no. > track no.
			@allTracks = sort {lc($a->album->namesort) cmp lc($b->album->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @allTracks;
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Sorting tracks took '.(time()-$sortStartTime).' seconds');
		main::idleStreams();
	}

	## Save tracks as static playlist ###

	# if PL with same name exists, add epoch time to PL name
	my $newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();
	if ($newStaticPL) {
		if ($prefs->get('savetoploverwrite')) {
			Slim::Control::Request::executeRequest(undef, ['playlists', 'delete', 'playlist_id:'.$newStaticPL->id])
		} else {
			my $timestamp = strftime "%Y-%m-%d--%H-%M-%S", localtime time;
			$staticPLname = $staticPLname.'_'.$timestamp;
		}
	}
	$newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();
	Slim::Control::Request::executeRequest(undef, ['playlists', 'new', 'name:'.$staticPLname]) if !$newStaticPL;
	$newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();

	my $setTracksStartTime = time();
	$newStaticPL->setTracks(\@allTracks);
	main::DEBUGLOG && $log->is_debug && $log->debug("setTracks took ".(time()-$setTracksStartTime).' seconds');
	$newStaticPL->update;
	main::idleStreams();

	my $scheduleWriteOfPlaylistStartTime = time();
	Slim::Player::Playlist::scheduleWriteOfPlaylist(undef, $newStaticPL);
	main::DEBUGLOG && $log->is_debug && $log->debug("scheduleWriteOfPlaylist took ".(time()-$scheduleWriteOfPlaylistStartTime).' seconds');

	main::INFOLOG && $log->is_info && $log->info('Saved static playlist "'.$staticPLname.'" with '.scalar(@allTracks).(scalar(@allTracks) == 1 ? ' track' : ' tracks').'. Task completed after '.(time()-$started)." seconds.\n\n");

	$prefs->set('status_savingtopl', 0);
	return;
}

## ---- library stats charts ---- ##

# ---- tracks ---- #

sub getDataTracksByAudioFileFormat {
	my $sqlstatement = "select tracks.content_type, count(distinct tracks.id) as nooftypes from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.content_type order by nooftypes desc";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrate {
	my $sqlstatement = "select round(bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.audio = 1 and tracks.bitrate is not null and tracks.bitrate > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by (case
			when round(tracks.bitrate/16000)*16 > 1400 then round(tracks.bitrate/160000)*160
			when round(tracks.bitrate/16000)*16 < 10 then 16
			else round(tracks.bitrate/16000)*16
			end)
		order by tracks.bitrate asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrateAudioFileFormat {
	my $dbh = Slim::Schema->dbh;
	my @result = ();
	my $genreFilter = $prefs->get('genrefilterid');
	my @fileFormatsWithBitrate = ();
	my $xLabelThresholds = [[1, 192], [192, 256], [256, 320], [320, 500], [500, 700], [700, 1000], [1000, 1201], [1201, 999999999999]];
	foreach my $xLabelThreshold (@{$xLabelThresholds}) {
		my $minVal = @{$xLabelThreshold}[0];
		my $maxVal = @{$xLabelThreshold}[1];
		my $xLabelName = '';
		if (@{$xLabelThreshold}[0] == 1) {
			$xLabelName = '<'.@{$xLabelThreshold}[1];
		} elsif (@{$xLabelThreshold}[1] == 999999999999) {
			$xLabelName = '>'.(@{$xLabelThreshold}[0]-1);
		} else {
			$xLabelName = @{$xLabelThreshold}[0]."-".((@{$xLabelThreshold}[1])-1);
		}
		my $subData = '';
		my $sqlbitrate = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlbitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlbitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlbitrate .= " where tracks.audio = 1 and tracks.bitrate is not null
				and round(tracks.bitrate/10000)*10 >= $minVal
				and round(tracks.bitrate/10000)*10 < $maxVal";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlbitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlbitrate .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir') group by tracks.content_type order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlbitrate);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormatsWithBitrate, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormatsWithBitrate;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	}

	my $sqlfileformats = "select distinct tracks.content_type from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlfileformats .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlfileformats .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlfileformats .= " where tracks.audio = 1 and tracks.remote = 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlfileformats .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlfileformats .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir') group by tracks.content_type order by tracks.content_type asc";
	my @fileFormatsComplete = ();
	my @fileFormatsNoBitrate = ();
	my $fileFormatName;
	my $sth = $dbh->prepare($sqlfileformats);
	$sth->execute();
	$sth->bind_columns(undef, \$fileFormatName);
	while ($sth->fetch()) {
		push (@fileFormatsComplete, $fileFormatName);
		push (@fileFormatsNoBitrate, $fileFormatName) unless grep{$_ eq $fileFormatName} @fileFormatsWithBitrate;
	}
	$sth->finish();
	my $subDataOthers = '';
	if (scalar(@fileFormatsNoBitrate) > 0) {
		foreach my $fileFormatNoBitrate (@fileFormatsNoBitrate) {
			my $sqlfileformatsnobitrate = "select count(distinct tracks.id) from tracks";
			my $selectedVL = $prefs->get('selectedvirtuallibrary');
			if ($selectedVL && $selectedVL ne '') {
				$sqlfileformatsnobitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
			}
			if (defined($genreFilter) && $genreFilter ne '') {
				$sqlfileformatsnobitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
			}
			$sqlfileformatsnobitrate .= " where tracks.audio = 1 and tracks.content_type=\"$fileFormatNoBitrate\"";
			my $decadeFilterVal = $prefs->get('decadefilterval');
			if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
				$sqlfileformatsnobitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
			}
			my $sth = $dbh->prepare($sqlfileformatsnobitrate);
			my $fileFormatCount = 0;
			$sth->execute();
			$sth->bind_columns(undef, \$fileFormatCount);
			$sth->fetch();
			$sth->finish();
			$subDataOthers = $subDataOthers.', "'.$fileFormatNoBitrate.'": '.$fileFormatCount;
		}
		$subDataOthers = '{"x": "'.string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_NOBITRATE").'"'.$subDataOthers.'}';
		push(@result, $subDataOthers);
	}

	my @wrapper = (\@result, \@fileFormatsComplete);
	main::DEBUGLOG && $log->is_debug && $log->debug('wrapper = '.Data::Dump::dump(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByBitrateAudioFileFormatScatter {
	my $dbh = Slim::Schema->dbh;
	my @result = ();
	my $sqlfileformats = "select distinct tracks.content_type from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlfileformats .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlfileformats .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlfileformats .= " where tracks.audio = 1 and tracks.bitrate is not null and tracks.bitrate > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlfileformats .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlfileformats .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir') group by tracks.content_type order by tracks.content_type asc";
	my @fileFormatsComplete = ();
	my @bitRates = ();
	my $fileFormatName;
	my $sth = $dbh->prepare($sqlfileformats);
	$sth->execute();
	$sth->bind_columns(undef, \$fileFormatName);
	while ($sth->fetch()) {
		push (@fileFormatsComplete, $fileFormatName);
	}
	$sth->finish();
	foreach my $thisFileFormat (@fileFormatsComplete) {
		my $subData = '';
		my $sqlbitrate = "select round(tracks.bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlbitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlbitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlbitrate .= " where tracks.audio = 1 and tracks.remote = 0 and tracks.content_type=\"$thisFileFormat\" and tracks.bitrate is not null and tracks.bitrate > 0";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlbitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlbitrate .= " group by (case
			when round(tracks.bitrate/16000)*16 > 1400 then round(tracks.bitrate/160000)*160
			when round(tracks.bitrate/16000)*16 < 10 then 16
			else round(tracks.bitrate/16000)*16
			end)
		order by tracks.bitrate asc;";
		my $sth = $dbh->prepare($sqlbitrate);
		#eval {
			$sth->execute();
			my $xAxisDataItem;
			my $yAxisDataItem;
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				if ($subData eq '') {
					$subData = '"'.$xAxisDataItem.'": '.$yAxisDataItem;
				} else {
					$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				}
				push (@bitRates, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @bitRates;
			}
			$sth->finish();
			$subData = '{'.$subData.'}';
			push(@result, $subData);
		#};
	}
	my @sortedbitRates = sort { $a <=> $b } @bitRates;

	my @wrapper = (\@result, \@sortedbitRates, \@fileFormatsComplete);
	main::DEBUGLOG && $log->is_debug && $log->debug('wrapper = '.Data::Dump::dump(\@wrapper));

	return \@wrapper;
}

sub getDataTracksBySampleRate {
	my $sqlstatement = "select tracks.samplerate||' Hz',count(distinct tracks.id) from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.audio = 1 and tracks.samplerate is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.samplerate||' Hz' order by tracks.samplerate asc;";

	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByFileSize {
	my $sqlstatement = "select cast(round(filesize/1048576) as int), count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.filesize > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by (case
			when round(filesize/1048576) < 1 then 1
			when round(filesize/1048576) > 1000 then 1000
			else round(filesize/1048576)
			end)
		order by tracks.filesize asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByFileSizeAudioFileFormat {
	my $dbh = Slim::Schema->dbh;
	my @result = ();
	my @fileFormats = ();
	my $genreFilter = $prefs->get('genrefilterid');

	# get track count for file sizes <= 100 MB
	foreach my $fileSize (1..100) {
		my $xLabelName = $fileSize;
		my $subData = '';
		my $sqlfilesize = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlfilesize .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlfilesize .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlfilesize .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.filesize > 0
				and case
						when $fileSize == 1 then round(tracks.filesize/1048576) <= $fileSize
						else round(tracks.filesize/1048576) == $fileSize
					end";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlfilesize .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlfilesize .= " group by tracks.content_type order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlfilesize);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormats, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormats;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	}

	# aggregate for files > 100 MB
		my $xLabelName = ' > 100';
		my $subData = '';
		my $sqlfilesize = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlfilesize .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlfilesize .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlfilesize .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.filesize > 0 and round(tracks.filesize/1048576) > 100";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlfilesize .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlfilesize .= " group by tracks.content_type order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlfilesize);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormats, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormats;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	my @wrapper = (\@result, \@fileFormats);
	main::DEBUGLOG && $log->is_debug && $log->debug('wrapper = '.Data::Dump::dump(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByGenre {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by nooftracks desc, genres.namesort asc limit ($rowLimit-1);";
	my $sqlResult = executeSQLstatement($sqlstatement, 3, 1);

	my $sum = 0;
	foreach my $hash ( @{$sqlResult} ) {
		$sum += $hash->{'yAxis'};
	}

	my $trackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$trackCountSQL .= " where tracks.audio = 1";
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$trackCountSQL .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$trackCountSQL .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCount = quickSQLcount($trackCountSQL);
	my $othersCount = $trackCount - $sum;
	push @{$sqlResult}, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_OTHERS'), 'yAxis' => $othersCount} unless ($othersCount <= 0);
	return $sqlResult;
}

sub getDataTracksMostPlayed {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select tracks.title, ifnull($dbTable.playCount, 0), tracks.id, contributors.name from tracks join contributors on contributors.id = tracks.primary_artist left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " order by $dbTable.playCount desc, tracks.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataTracksMostPlayedAPC {
	return getDataTracksMostPlayed(1);
}

sub getDataTracksMostSkippedAPC {
	my $sqlstatement = "select tracks.title, ifnull(alternativeplaycount.skipCount, 0), tracks.id, contributors.name from tracks join contributors on contributors.id = tracks.primary_artist left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " order by alternativeplaycount.skipCount desc, tracks.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataTracksByDPSV {
	my $sqlstatement = "select ifnull(alternativeplaycount.dynPSval, 0), count(distinct tracks.id) as nooftracks from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.audio = 1 and alternativeplaycount.dynPSval is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by ifnull(alternativeplaycount.dynPSval, 0) order by ifnull(alternativeplaycount.dynPSval, 0) asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByRating {
	my $starString = string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_STAR');
	my $starsString = string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_STARS');
	my $sqlstatement = "select case
		when CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 1 then (ifnull(tracks_persistent.rating, 0)/20)||'$starString'
		when (CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 0 or CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 2 or CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 3 or CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 4 or CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 = 5 ) then (ifnull(tracks_persistent.rating, 0)/20)||'$starsString'
		else (CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20)||'$starsString'
	end, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20
		order by CAST(ifnull(tracks_persistent.rating, 0) as REAL)/20 desc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByYear {
	my $sqlstatement = "select case when ifnull(tracks.year, 0) > 0 then tracks.year else 'Unknown' end, count(distinct tracks.id) as nooftracks, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by tracks.year asc;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataTracksByDateAdded {
	my $sqlstatement = "select strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime') as dateadded, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks_persistent.added > 0 and tracks_persistent.added is not null group by strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime')
		order by strftime ('%Y',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%m',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%d',tracks_persistent.added, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByDateLastModified {
	my $sqlstatement = "select case when ifnull(tracks.timestamp, 0) < 315532800 then 'Unkown' else strftime('%d-%m-%Y',tracks.timestamp, 'unixepoch', 'localtime') end, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " where tracks.timestamp > 0 and tracks.timestamp is not null
		group by strftime('%d-%m-%Y',tracks.timestamp, 'unixepoch', 'localtime')
		order by strftime ('%Y',tracks.timestamp, 'unixepoch', 'localtime') asc, strftime('%m',tracks.timestamp, 'unixepoch', 'localtime') asc, strftime('%d',tracks.timestamp, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

# ---- artists ---- #

sub getDataArtistWithMostTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks, contributors.id from contributors join contributor_track on contributor_track.contributor = contributors.id and contributor_track.role in (1,5,6) join tracks on tracks.id = contributor_track.track";
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " where contributors.id is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and contributors.name is not '$VAstring' and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by contributors.name order by nooftracks desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistWithMostAlbums {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct albums.id) as noofalbums, contributors.id from albums join tracks on tracks.album = albums.id join contributors on contributors.id = albums.contributor join contributor_track on contributor_track.contributor = albums.contributor and contributor_track.role in (1,5)";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where ifnull(albums.compilation, 0) is not 1 and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by contributors.name order by noofalbums desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistWithMostRatedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks, contributors.id from tracks left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring' and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by nooftracks desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsHighestPercentageRatedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, contributors.id from tracks left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist having count(distinct tracks.id) >= $minArtistTracks order by ratedpercentage desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, contributors.id from tracks left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist having count(distinct tracks.id) >= $minArtistTracks order by procrating desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithTopRatedTracksTotal {
	return getDataArtistsWithTopRatedTracksAvg(1);
}

sub getDataArtistsWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks, contributors.id from tracks left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring' and $dbTable.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by nooftracks desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithMostPlayedTracksAPC {
	return getDataArtistsWithMostPlayedTracks(1);
}

sub getDataArtistsWithTracksCompletelyPartlyNonePlayed {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my @result = ();
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';

	my $sqlstatement_shared = "select count (distinct playedtracks.artistname) from (select distinct contributors.name as artistname, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}

	my $sql_completelyplayed = $sqlstatement_shared . " group by tracks.primary_artist having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " group by tracks.primary_artist having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " group by tracks.primary_artist having playedpercentage == 0) as playedtracks";

	my $artistcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $artistcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $artistcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_COMPLETELY'), 'yAxis' => $artistcount_completelyplayed}) unless ($artistcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_PARTIALLY'), 'yAxis' => $artistcount_partiallyplayed}) unless ($artistcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_NOTPLAYED'), 'yAxis' => $artistcount_notplayed}) unless ($artistcount_notplayed == 0);

	return \@result;
}

sub getDataArtistsWithTracksCompletelyPartlyNonePlayedAPC {
	return getDataArtistsWithTracksCompletelyPartlyNonePlayed(1);
}

sub getDataArtistsHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, contributors.id from tracks left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist having count(distinct tracks.id) >= $minArtistTracks and playedpercentage < 100 order by playedpercentage desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsHighestPercentagePlayedTracksAPC {
	return getDataArtistsHighestPercentagePlayedTracks(1);
}

sub getDataArtistsWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, $func(ifnull($dbTable.playCount,0)) as procplaycount, contributors.id from tracks left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by procplaycount desc, contributors.namesort asc limit $rowLimit;";
$log->warn(Data::Dump::dump($sqlstatement));
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithMostPlayedTracksAverageAPC {
	return getDataArtistsWithMostPlayedTracksAverage(1);
}

sub getDataArtistsWithMostPlayedTracksTotal {
	return getDataArtistsWithMostPlayedTracksAverage(0,1);
}

sub getDataArtistsWithMostPlayedTracksTotalAPC {
	return getDataArtistsWithMostPlayedTracksAverage(1,1);
}

sub getDataArtistsWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name,";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount," : " count(distinct tracks.id) as nooftracks,";
	$sqlstatement .= " contributors.id from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring' and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithTopTotalSkipCountAPC {
	return getDataArtistsWithMostSkippedTracksAPC(1);
}

sub getDataArtistsHighestPercentageSkippedTracksAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, contributors.id from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist having count(distinct tracks.id) >= $minArtistTracks order by skippedpercentage desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsWithMostSkippedTracksAverageAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, contributors.id from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by avgskipcount desc, contributors.namesort asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsRatingPlaycount {
	my ($useAPC, $agg) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select t.* from (select $aggFunc(ifnull($dbTable.playCount,0)) as procplaycount, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, contributors.name from tracks";
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5" if $useAPC;
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist) as t where (t.procplaycount >= 0.05 and t.procrating >= 0.05);";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataArtistsRatingPlaycountAPC {
	return getDataArtistsRatingPlaycount(1);
}

sub getDataArtistsRatingPlaycountTotal {
	return getDataArtistsRatingPlaycount(0,1);
}

sub getDataArtistsRatingPlaycountTotalAPC {
	return getDataArtistsRatingPlaycountAPC(1,1);
}

sub getDataArtistsHighestAvgDpsvAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, contributors.id from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and alternativeplaycount.dynPSval is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by avgdpsv desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataArtistsLowestAvgDpsvAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, contributors.id from tracks left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and alternativeplaycount.dynPSval is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist order by avgdpsv asc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);

}

# ---- albums ---- #

sub getDataAlbumsByYear {
	my $sqlstatement = "select case when albums.year > 0 then albums.year else 'Unknown' end, count(distinct albums.id) as noofalbums, ifnull(albums.year, 0) from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.year order by albums.year asc";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataAlbumsWithMostTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title order by nooftracks desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsByReleaseType {
	my $sqlstatement = "select albums.release_type, count(distinct albums.id) as noofalbums from albums join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.release_type order by noofalbums desc";
	my $rlTypeArr = executeSQLstatement($sqlstatement);

	foreach my $thisRLtype (@{$rlTypeArr}) {
		$thisRLtype->{'xAxis'} = _releaseTypeName($thisRLtype->{'xAxis'});
	}
	return $rlTypeArr;
}

sub getDataAlbumsWithMostRatedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title order by nooftracks desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsHighestPercentageRatedTracks {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title having count(distinct tracks.id) >= $minAlbumTracks order by ratedpercentage desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select albums.title, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title having count(distinct tracks.id) >= $minAlbumTracks order by procrating desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithTopRatedTracksTotal {
	return getDataAlbumsWithTopRatedTracksAvg(1);
}

sub getDataAlbumsWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title order by nooftracks desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithMostPlayedTracksAPC {
	return getDataAlbumsWithMostPlayedTracks(1);
}

sub getDataAlbumsWithTracksCompletelyPartlyNonePlayed {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my @result = ();
	my $sqlstatement_shared = "select count (distinct playedtracks.albumtitle) from (select distinct albums.title as albumtitle, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from albums join tracks on tracks.album = albums.id left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement_shared .= " group by albums.title";

	my $sql_completelyplayed = $sqlstatement_shared . " having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " having playedpercentage == 0) as playedtracks";

	my $albumcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $albumcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $albumcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_COMPLETELY'), 'yAxis' => $albumcount_completelyplayed}) unless ($albumcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_PARTIALLY'), 'yAxis' => $albumcount_partiallyplayed}) unless ($albumcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_NOTPLAYED'), 'yAxis' => $albumcount_notplayed}) unless ($albumcount_notplayed == 0);

	return \@result;
}

sub getDataAlbumsWithTracksCompletelyPartlyNonePlayedAPC {
	return getDataAlbumsWithTracksCompletelyPartlyNonePlayed(1);
}

sub getDataAlbumsHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title having count(distinct tracks.id) >= $minAlbumTracks and playedpercentage < 100 order by playedpercentage desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsHighestPercentagePlayedTracksAPC {
	return getDataAlbumsHighestPercentagePlayedTracks(1);
}

sub getDataAlbumsWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $sqlstatement = "select albums.title, $func(ifnull($dbTable.playCount,0)) as procplaycount, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title order by procplaycount desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithMostPlayedTracksAverageAPC {
	return getDataAlbumsWithMostPlayedTracksAverage(1);
}

sub getDataAlbumsWithMostPlayedTracksTotal {
	return getDataAlbumsWithMostPlayedTracksAverage(0,1);
}

sub getDataAlbumsWithMostPlayedTracksTotalAPC {
	return getDataAlbumsWithMostPlayedTracksAverage(1,1);
}

sub getDataAlbumsWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $sqlstatement = "select albums.title,";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount," : " count(distinct tracks.id) as nooftracks,";
	$sqlstatement .= " albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithTopTotalSkipCountAPC {
	return getDataAlbumsWithMostSkippedTracksAPC(1);
}

sub getDataAlbumsHighestPercentageSkippedTracksAPC {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title having count(distinct tracks.id) >= $minAlbumTracks order by skippedpercentage desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select albums.title, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where albums.title is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title order by avgskipcount desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsHighestAvgDpsvAPC {
	my $sqlstatement = "select albums.title, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where albums.title is not null and alternativeplaycount.dynPSval is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title order by avgdpsv desc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataAlbumsLowestAvgDpsvAPC {
	my $sqlstatement = "select albums.title, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, albums.id, contributors.name from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = albums.contributor left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where albums.title is not null and alternativeplaycount.dynPSval is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by albums.title order by avgdpsv asc, albums.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

# ---- works ---- #

sub getDataWorksByYear {
	my $sqlstatement = "select case when tracks.year > 0 then tracks.year else 'Unknown' end, count(distinct tracks.work), ifnull(tracks.year, 0) from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by tracks.year asc";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataComposersWithMostWorks {
	my $sqlstatement = "select distinct contributors.name, count(distinct works.id) as noofworks, works.composer from works join tracks on tracks.work = works.id join contributors on works.composer = contributors.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by contributors.name order by noofworks desc, contributors.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataWorksWithMostRatedTracks {
	my $sqlstatement = "select works.title, count(distinct tracks.id) as nooftracks, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by works.id
		order by nooftracks desc, works.titlesort asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksHighestPercentageRatedTracks {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct works.title, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id having count(distinct tracks.id) >= $minAlbumTracks order by ratedpercentage desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select works.title, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id having count(distinct tracks.id) >= $minAlbumTracks order by procrating desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithTopRatedTracksTotal {
	return getDataWorksWithTopRatedTracksAvg(1);
}

sub getDataWorksWithMostPerformances {
	my $sqlstatement = "select works.title, (select count(distinct album||work||coalesce(performance,1)) from tracks where tracks.work = works.id) as noofperformances, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by works.id order by noofperformances desc, contributors.namesort asc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select works.title, count(distinct tracks.id) as nooftracks, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and contributors.name is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by works.id order by nooftracks desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithMostPlayedTracksAPC {
	return getDataWorksWithMostPlayedTracks(1);
}

sub getDataWorksWithTracksCompletelyPartlyNonePlayed {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my @result = ();
	my $sqlstatement_shared = "select count (distinct playedtracks.worktitle) from (select distinct works.title as worktitle, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from works join tracks on tracks.work = works.id left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join contributors on contributors.id = works.composer";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement_shared .= " group by works.id";
	my $sql_completelyplayed = $sqlstatement_shared . " having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " having playedpercentage == 0) as playedtracks";

	my $workcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $workcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $workcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_WORKS_PLAYED_COMPLETELY'), 'yAxis' => $workcount_completelyplayed}) unless ($workcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_WORKS_PLAYED_PARTIALLY'), 'yAxis' => $workcount_partiallyplayed}) unless ($workcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_WORKS_PLAYED_NOTPLAYED'), 'yAxis' => $workcount_notplayed}) unless ($workcount_notplayed == 0);

	return \@result;
}

sub getDataWorksWithTracksCompletelyPartlyNonePlayedAPC {
	return getDataWorksWithTracksCompletelyPartlyNonePlayed(1);
}

sub getDataWorksHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct works.title, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, works.id, contributors.name from works
		join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id having count(distinct tracks.id) >= $minAlbumTracks and playedpercentage < 100 order by playedpercentage desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksHighestPercentagePlayedTracksAPC {
	return getDataWorksHighestPercentagePlayedTracks(1);
}

sub getDataWorksWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $sqlstatement = "select works.title, $func(ifnull($dbTable.playCount,0)) as procplaycount, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id order by procplaycount desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithMostPlayedTracksAverageAPC {
	return getDataWorksWithMostPlayedTracksAverage(1);
}

sub getDataWorksWithMostPlayedTracksTotal {
	return getDataWorksWithMostPlayedTracksAverage(0,1);
}

sub getDataWorksWithMostPlayedTracksTotalAPC {
	return getDataWorksWithMostPlayedTracksAverage(1,1);
}

sub getDataWorksWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $sqlstatement = "select works.title,";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount," : " count(distinct tracks.id) as nooftracks,";
	$sqlstatement .= " works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by works.id order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithTopTotalSkipCountAPC {
	return getDataWorksWithMostSkippedTracksAPC(1);
}

sub getDataWorksHighestPercentageSkippedTracksAPC {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct works.title, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id having count(distinct tracks.id) >= $minAlbumTracks order by skippedpercentage desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select works.title, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where works.title is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id order by avgskipcount desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksHighestAvgDpsvAPC {
	my $sqlstatement = "select works.title, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where works.title is not null and alternativeplaycount.dynPSval is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id order by avgdpsv desc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

sub getDataWorksLowestAvgDpsvAPC {
	my $sqlstatement = "select works.title, avg(ifnull(alternativeplaycount.dynPSval,0)) as avgdpsv, works.id, contributors.name from works join tracks on tracks.work = works.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on contributors.id = works.composer left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where works.title is not null and alternativeplaycount.dynPSval is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.work is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by works.id order by avgdpsv asc, works.titlesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 4);
}

# ---- genres ---- #

sub getDataGenresWithMostTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by nooftracks desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithMostAlbums {
	my $sqlstatement = "select genres.name, count(distinct albums.id) as noofalbums, genres.id from albums join tracks on tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by noofalbums desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithMostRatedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name order by nooftracks desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresHighestPercentageRatedTracks {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by ratedpercentage desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $sqlstatement = "select genres.name, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by procrating desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithTopRatedTracksTotal {
	return getDataGenresWithTopRatedTracksAvg(1);
}

sub getDataGenresWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name order by nooftracks desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithMostPlayedTracksAPC {
	return getDataGenresWithMostPlayedTracks(1);
}

sub getDataGenresHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by playedpercentage desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresHighestPercentagePlayedTracksAPC {
	return getDataGenresHighestPercentagePlayedTracks(1);
}

sub getDataGenresWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $sqlstatement = "select genres.name, $func(ifnull($dbTable.playCount,0)) as procplaycount, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by procplaycount desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithMostPlayedTracksAverageAPC {
	return getDataGenresWithMostPlayedTracksAverage(1);
}

sub getDataGenresWithMostPlayedTracksTotal {
	return getDataGenresWithMostPlayedTracksAverage(0,1);
}

sub getDataGenresWithMostPlayedTracksTotalAPC {
	return getDataGenresWithMostPlayedTracksAverage(1,1);
}

sub getDataGenresWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $sqlstatement = "select genres.name,";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount," : " count(distinct tracks.id) as nooftracks,";
	$sqlstatement .= " genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithTopTotalSkipCountAPC {
	return getDataGenresWithMostSkippedTracksAPC(1);
}

sub getDataGenresHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by skippedpercentage desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select genres.name, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 join genre_track on genre_track.track = tracks.id join genres on genres.id = genre_track.genre where genres.name is not null and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by avgskipcount desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataGenresWithTopAverageBitrate {
	my $sqlstatement = "select genres.name, avg(round(ifnull(tracks.bitrate,0)/16000)*16) as avgbitrate, genres.id from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on tracks.id=genre_track.track join genres on genre_track.genre=genres.id where genres.name is not null and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by genres.name order by avgbitrate desc, genres.namesort asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

# ---- years ---- #

sub getDataYearsWithMostTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by nooftracks desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithMostAlbums {
	my $sqlstatement = "select tracks.year, count(distinct tracks.album) as noofalbums, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.year > 0 and tracks.year is not null and tracks.album is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and (tracks.audio = 1 or tracks.extid is not null) group by tracks.year order by noofalbums desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithMostRatedTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks_persistent.rating > 0 group by tracks.year order by nooftracks desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsHighestPercentageRatedTracks {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by ratedpercentage desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $sqlstatement = "select tracks.year, $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by procrating desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithTopRatedTracksTotal {
	return getDataYearsWithTopRatedTracksAvg(1);
}

sub getDataYearsWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0 group by tracks.year order by nooftracks desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithMostPlayedTracksAPC {
	return getDataYearsWithMostPlayedTracks(1);
}

sub getDataYearsHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by playedpercentage desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsHighestPercentagePlayedTracksAPC {
	return getDataYearsHighestPercentagePlayedTracks(1);
}

sub getDataYearsWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $sqlstatement = "select tracks.year, $func(ifnull($dbTable.playCount,0)) as procplaycount, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by procplaycount desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithMostPlayedTracksAverageAPC {
	return getDataYearsWithMostPlayedTracksAverage(1);
}

sub getDataYearsWithMostPlayedTracksTotal {
	return getDataYearsWithMostPlayedTracksAverage(0,1);
}

sub getDataYearsWithMostPlayedTracksTotalAPC {
	return getDataYearsWithMostPlayedTracksAverage(1,1);
}

sub getDataYearsWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $sqlstatement = "select tracks.year,";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount," : " count(distinct tracks.id) as nooftracks,";
	$sqlstatement .= " tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0 group by tracks.year order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithTopTotalSkipCountAPC {
	return getDataYearsWithMostSkippedTracksAPC(1);
}

sub getDataYearsHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by skippedpercentage desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

sub getDataYearsWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select tracks.year, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, tracks.year from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by tracks.year order by avgskipcount desc, tracks.year asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3, 1);
}

# ---- decades ---- #

sub getDataDecadesWithMostTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostAlbums {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.album) as noofalbums from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where tracks.year > 0 and tracks.year is not null and tracks.album is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and (tracks.audio = 1 or tracks.extid is not null) group by cast(((tracks.year/10)*10) as int)||'s' order by noofalbums desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostRatedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks_persistent.rating > 0 group by cast(((tracks.year/10)*10) as int)||'s' order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentageRatedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by ratedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithTopRatedTracksAvg {
	my $agg = shift;
	my $aggFunc = $agg ? 'sum' : 'avg';
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', $aggFunc(ifnull(tracks_persistent.rating,0)/20) as procrating from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by procrating desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithTopRatedTracksTotal {
	return getDataDecadesWithTopRatedTracksAvg(1);
}

sub getDataDecadesWithMostPlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and $dbTable.playCount > 0 group by cast(((tracks.year/10)*10) as int)||'s' order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAPC {
	return getDataDecadesWithMostPlayedTracks(1);
}

sub getDataDecadesHighestPercentagePlayedTracks {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull($dbTable.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by playedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentagePlayedTracksAPC {
	return getDataDecadesHighestPercentagePlayedTracks(1);
}

sub getDataDecadesWithMostPlayedTracksAverage {
	my ($useAPC, $totalabs) = @_;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $func = $totalabs ? 'sum' : 'avg';
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', $func(ifnull($dbTable.playCount,0)) as procplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by procplaycount desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAverageAPC {
	return getDataDecadesWithMostPlayedTracksAverage(1);
}

sub getDataDecadesWithMostPlayedTracksTotal {
	return getDataDecadesWithMostPlayedTracksAverage(0,1);
}

sub getDataDecadesWithMostPlayedTracksTotalAPC {
	return getDataDecadesWithMostPlayedTracksAverage(1,1);
}

sub getDataDecadesWithMostSkippedTracksAPC {
	my $totalabs = shift;
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s',";
	$sqlstatement .= $totalabs ? " sum(ifnull(alternativeplaycount.skipCount,0)) as aggskipcount" : " count(distinct tracks.id) as nooftracks";
	$sqlstatement .= " from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and alternativeplaycount.skipCount > 0 group by cast(((tracks.year/10)*10) as int)||'s' order by";
	$sqlstatement .= $totalabs ? " aggskipcount" : " nooftracks";
	$sqlstatement .= " desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithTopTotalSkipCountAPC {
	return getDataDecadesWithMostSkippedTracksAPC(1);
}

sub getDataDecadesHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by skippedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5 where tracks.year > 0 and tracks.year is not null and (tracks.audio = 1 or tracks.extid is not null) and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' group by cast(((tracks.year/10)*10) as int)||'s' order by avgskipcount desc, cast(((tracks.year/10)*10) as int)||'s' asc limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- misc. ---- #

sub getDataListeningTimes {
	my $useAPC = shift;
	my $dbTable = $useAPC ? 'alternativeplaycount' : 'tracks_persistent';
	my $sqlstatement = "select strftime('%H:%M',$dbTable.lastPlayed, 'unixepoch', 'localtime') as timelastplayed, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join $dbTable on $dbTable.urlmd5 = tracks.urlmd5 where $dbTable.lastPlayed > 0 and $dbTable.lastPlayed is not null group by strftime('%H:%M',$dbTable.lastPlayed, 'unixepoch', 'localtime') order by strftime ('%H',$dbTable.lastPlayed, 'unixepoch', 'localtime') asc, strftime('%M',$dbTable.lastPlayed, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataListeningTimesAPC {
	return getDataListeningTimes(1);
}

sub getDataTrackTitleMostFrequentWords {
	my $dbh = Slim::Schema->dbh;
	my $sqlstatement = "select tracks.titlesearch from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where length(tracks.titlesearch) > 2 and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.titlesearch";
	my $thisTitle;
	my %frequentwords;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisTitle);
	while ($sth->fetch()) {
		next unless $thisTitle;
		my @words = split /\W+/, $thisTitle; #skip non-word characters
		foreach my $word(@words){
			chomp $word;
			$word = lc $word;
			$word =~ s/^\s+|\s+$//g; #remove beginning/trailing whitespace
			next if (length $word < 3 || $ignoreCommonWords{$word});
			$frequentwords{$word} ||= 0;
			$frequentwords{$word}++;
		}
	}

	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or $a cmp $b} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
		last if scalar @keys >= 50;
	};

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(\@keys));
	return \@keys;
}

sub getDataTrackLyricsMostFrequentWords {
	my $dbh = Slim::Schema->dbh;
	my $sqlstatement = "select tracks.lyrics from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where length(tracks.lyrics) > 15 and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.titlesearch";
	my $lyrics;
	my %frequentwords;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$lyrics);
	while ($sth->fetch()) {
		next unless $lyrics;
		my @words = split /\W+/, $lyrics; #skip non-word characters
		foreach my $word(@words){
			chomp $word;
			$word = lc $word;
			$word =~ s/^\s+|\s+$//g; #remove beginning/trailing whitespace
			next if (length $word < 3 || $ignoreCommonWords{$word});
			$frequentwords{$word} ||= 0;
			$frequentwords{$word}++;
		}
	}
	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or $a cmp $b} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
		last if scalar @keys >= 50;
	};

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(\@keys));
	return \@keys;
}

#####################
# helpers

sub executeSQLstatement {
	my @result = ();
	my $dbh = Slim::Schema->dbh;
	my $sqlstatement = shift;
	my $valuesToBind = shift || 2;
	my $getIDs = shift;
	#eval {
		my $sth = $dbh->prepare($sqlstatement);
		$sth->execute() or do {
			$sqlstatement = undef;
		};
		my $xAxisDataItem; # string values
		my $yAxisDataItem; # numeric values
		my $xAxisDataItemID; # LMS object ids (artist, album, genre, track) for xAxis items
		my $labelExtraDataItem; # extra data for chart labels
		if ($valuesToBind > 2) {
			if ($valuesToBind == 3) {
				if ($getIDs) {
					$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem, \$xAxisDataItemID);
					while ($sth->fetch()) {
						utf8::decode($xAxisDataItem);
						push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem, 'itemID' => $xAxisDataItemID}) unless ($yAxisDataItem == 0);
					}
				} else {
					$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem, \$labelExtraDataItem);
					while ($sth->fetch()) {
						utf8::decode($xAxisDataItem); utf8::decode($labelExtraDataItem);
						push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem, 'labelExtra' => $labelExtraDataItem}) unless ($yAxisDataItem == 0);
					}
				}
			}
			if ($valuesToBind == 4) {
				$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem, \$xAxisDataItemID, \$labelExtraDataItem);
				while ($sth->fetch()) {
					utf8::decode($xAxisDataItem); utf8::decode($labelExtraDataItem);
					push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem, 'itemID' => $xAxisDataItemID, 'labelExtra' => $labelExtraDataItem}) unless ($yAxisDataItem == 0);
				}
			}
		} else {
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem}) unless ($yAxisDataItem == 0);
			}
		}
		$sth->finish();
	#};
	main::DEBUGLOG && $log->is_debug && $log->debug('SQL result = '.Data::Dump::dump(\@result));
	main::DEBUGLOG && $log->is_debug && $log->debug('Got '.scalar(@result).' items');
	return \@result;
}

sub quickSQLcount {
	my $dbh = Slim::Schema->dbh;
	my $sqlstatement = shift;
	my $thisCount;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisCount);
	$sth->fetch();
	$sth->finish();
	return $thisCount;
}

sub getVirtualLibraries {
	my @items;
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	main::DEBUGLOG && $log->is_debug && $log->debug('ALL virtual libraries: '.Data::Dump::dump($libraries));

	while (my ($k, $v) = each %{$libraries}) {
		my $count = Slim::Music::VirtualLibraries->getTrackCount($k);
		my $name = Slim::Music::VirtualLibraries->getNameForId($k);
		my $displayName = Slim::Utils::Unicode::utf8decode($name, 'utf8').' ('.Slim::Utils::Misc::delimitThousands($count).($count == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_TRACK") : ' '.string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_TRACKS")).')';
		main::DEBUGLOG && $log->is_debug && $log->debug("VL: ".$displayName);

		push @items, {
			'name' => $displayName,
			'sortName' => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
			'library_id' => $k,
		};
	}
	push @items, {
		'name' => string("PLUGIN_VISUALSTATISTICS_VL_COMPLETELIB_NAME"),
		'sortName' => " Complete Library",
		'library_id' => undef,
	};
	@items = sort { $a->{'sortName'} cmp $b->{'sortName'} } @items;
	return \@items;
}

sub getGenres {
	my @genres = ();
	my $query = ['genres', 0, 999_999];
	my $request;

	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	push @{$query}, 'library_id:'.$selectedVL if ($selectedVL && $selectedVL ne '');
	$request = Slim::Control::Request::executeRequest(undef, $query);

	foreach my $genre ( @{ $request->getResult('genres_loop') || [] } ) {
		push (@genres, {'name' => $genre->{'genre'}, 'id' => $genre->{'id'}});
	}
	push @genres, {
		'name' => string("PLUGIN_VISUALSTATISTICS_CHARTFILTER_ALLGENRES"),
		'id' => undef,
	};
	@genres = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @genres;
	main::DEBUGLOG && $log->is_debug && $log->debug('genres list = '.Data::Dump::dump(\@genres));
	return \@genres;
}

sub getDecades {
	my $dbh = Slim::Schema->dbh;
	my @decades = ();
	my $decadesQueryResult = {};
	my $unknownString = string('PLUGIN_VISUALSTATISTICS_CHARTFILTER_UNKNOWN');

	my $sql_decades = "select cast(((ifnull(tracks.year,0)/10)*10) as int) as decade,case when tracks.year>0 then cast(((tracks.year/10)*10) as int)||'s' else '$unknownString' end as decadedisplayed from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sql_decades .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sql_decades .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sql_decades .= " where tracks.audio = 1 group by decade order by decade desc";

	my ($decade, $decadeDisplayName);
	eval {
		my $sth = $dbh->prepare($sql_decades);
		$sth->execute() or do {
			$sql_decades = undef;
		};
		$sth->bind_columns(undef, \$decade, \$decadeDisplayName);

		while ($sth->fetch()) {
			push (@decades, {'name' => $decadeDisplayName, 'val' => $decade});
		}
		$sth->finish();
		main::DEBUGLOG && $log->is_debug && $log->debug('decadesQueryResult = '.Data::Dump::dump($decadesQueryResult));
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr\n$@");
		return 'error';
	}
	unshift @decades, {
		'name' => string("PLUGIN_VISUALSTATISTICS_CHARTFILTER_ALLDECADES"),
		'val' => undef,
	};
	main::DEBUGLOG && $log->is_debug && $log->debug('decade list = '.Data::Dump::dump(\@decades));
	return \@decades;
}

sub prettifyTime {
	my $timeinseconds = shift;
	my $seconds = (int($timeinseconds)) % 60;
	my $minutes = (int($timeinseconds / (60))) % 60;
	my $hours = (int($timeinseconds / (60*60))) % 24;
	my $days = (int($timeinseconds / (60*60*24))) % 7;
	my $weeks = (int($timeinseconds / (60*60*24*7))) % 52;
	my $years = (int($timeinseconds / (60*60*24*365))) % 10;
	my $prettyTime = (($years > 0 ? $years.($years == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEYEAR").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEYEARS").'  ') : '').($weeks > 0 ? $weeks.($weeks == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEWEEK").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEWEEKS").'  ') : '').($days > 0 ? $days.($days == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEDAY").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEDAYS").'  ') : '').($hours > 0 ? $hours.($hours == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEHOUR").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEHOURS").'  ') : '').($minutes > 0 ? $minutes.($minutes == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMIN").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMINS").'  ') : '').($seconds > 0 ? $seconds.($seconds == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMESEC") : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMESECS")) : ''));
	return $prettyTime;
}

sub _releaseTypeName {
	my $releaseType = shift;

	my $nameToken = uc($releaseType);
	$nameToken =~ s/[^a-z_0-9]/_/ig;
	my $name;
	foreach ('RELEASE_TYPE_' . $nameToken, 'RELEASE_TYPE_CUSTOM_' . $nameToken, $nameToken) {
		$name = string($_) if Slim::Utils::Strings::stringExists($_);
		last if $name;
	}
	return $name || $releaseType;
}

1;
