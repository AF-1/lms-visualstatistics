#
# Visual Statistics
#
# (c) 2021 AF-1
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
use URI::Escape;
use Time::HiRes qw(time);
use Data::Dumper;

use constant LIST_URL => 'plugins/VisualStatistics/html/list.html';
use constant TEXTDATA_URL => 'plugins/VisualStatistics/html/list.html';
use constant JSON_URL => 'plugins/VisualStatistics/getdata.html';

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.visualstatistics',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_VISUALSTATISTICS',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.visualstatistics');

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	Slim::Web::Pages->addPageFunction(LIST_URL, \&handleWeb);
	Slim::Web::Pages->addPageFunction(JSON_URL, \&handleJSON);
	Slim::Web::Pages->addPageLinks('plugins', {'PLUGIN_VISUALSTATISTICS' => LIST_URL});
}

sub handleWeb {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	my $host = $params->{host} || (Slim::Utils::Network::serverAddr() . ':' . preferences('server')->get('httpport'));
	$params->{squeezebox_server} = 'http://' . $host . '/' . JSON_URL;

	my $ratedTrackCountSQL = "select count(*) from tracks,tracks_persistent where tracks.url=tracks_persistent.url and audio=1 and rating>0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL) || 0;
	$params->{ratedtrackcount} = $ratedTrackCount;

	return Slim::Web::HTTP::filltemplatefile($params->{'path'}, $params);
}

sub handleJSON {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	my $response = {error => 'invalid arguments'};
	my $querytype = $params->{content};
	$log->debug('querytype = '.Dumper($querytype));
	my $started = time();

	if ($querytype) {
		$response = {
			error => 0,
			msg => $querytype,
			results => eval("$querytype()"),
		};
	}

	$log->debug('JSON response = '.Dumper($response));
	$log->info('exec time for query "'.$querytype.'" = '.(time()-$started).' seconds.');
	my $content = $params->{callback} ? $params->{callback}.'('.JSON::XS->new->ascii->encode($response).')' : JSON::XS->new->ascii->encode($response);
	$httpResponse->header('Content-Length' => length($content));

	return \$content;
}

my $rowLimit = 50;

# ---- artists ------- #

sub getDataArtistWithMostTracks {
	my $sqlstatement = "select contributors.name as roles, count(distinct tracks.id) as nooftracks from contributors
		left join contributor_track on
			contributors.id=contributor_track.contributor and contributor_track.role in (1,6)
		left join tracks on
			contributor_track.track=tracks.id
		left join albums on
			albums.id=tracks.album
		where
			contributors.id is not null
		group by contributors.id
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostAlbums {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select contributors.name, count(distinct albums.id) as noofalbums from albums
		join contributors on
			albums.contributor = contributors.id
		left join contributor_track on
			albums.contributor=contributor_track.contributor and contributor_track.role in (1,5)
		where
			compilation is not 1
			and contributors.name is not '$VAstring'
		group by contributors.name
		order by noofalbums desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostRatedTracks {
	my $sqlstatement = "select contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
			and tracks_persistent.rating > 0
		group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTopRatedTracksAll {
	my $sqlstatement = "select contributors.name, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
		group by tracks.primary_artist
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select contributors.name, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
			and tracks_persistent.rating > 0
		group by tracks.primary_artist
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracks {
	my $sqlstatement = "select contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
			and tracks_persistent.playCount > 0
		group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracksAverage {
	my $sqlstatement = "select contributors.name, avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
		group by tracks.primary_artist
		order by avgplaycount desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsRatingPlaycount {
	my $sqlstatement = "select t.* from (select avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating, contributors.name from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join contributors on
			tracks.primary_artist = contributors.id
		where
			audio=1
		group by tracks.primary_artist) as t
		where (t.avgplaycount >= 0.05 and t.avgrating >= 0.05);";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- albums ---- #

sub getDataAlbumsByYear {
	my $sqlstatement = "select case when year>0 then year else 'Unknown' end, count(distinct albums.id) as noofalbums from albums
		group by albums.year
		order by albums.year asc";
	return executeSQLstatement($sqlstatement);
}

sub getDataAlbumsWithMostTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		where
			albums.title is not null
			and audio = 1
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostRatedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			albums.title is not null
			and tracks_persistent.rating > 0
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTopRatedTracksAll {
	my $sqlstatement = "select albums.title, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			albums.title is not null
		group by albums.title
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select albums.title, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			albums.title is not null
			and tracks_persistent.rating > 0
		group by albums.title
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			albums.title is not null
			and tracks_persistent.playCount > 0
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracksAverage {
	my $sqlstatement = "select albums.title, avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount, contributors.name from albums
		join tracks on
			tracks.album=albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			albums.title is not null
		group by albums.title
		order by avgplaycount desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- genres ---- #

sub getDataGenresWithMostTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			audio=1
			and genres.name is not null
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostAlbums {
	my $sqlstatement = "select genres.name, count(distinct albums.id) as noofalbums from albums
		left join tracks on
			tracks.album=albums.id
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			genres.name is not null
		group by genres.name
		order by noofalbums desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostRatedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			genres.name is not null
			and tracks_persistent.rating > 0
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopRatedTracksAll {
	my $sqlstatement = "select genres.name, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			audio=1
			and genres.name is not null
		group by genres.name
		order by avgrating desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select genres.name, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			audio=1
			and genres.name is not null
			and tracks_persistent.rating > 0
		group by genres.name
		order by avgrating desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			audio=1
			and genres.name is not null
			and tracks_persistent.playCount > 0
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracksAverage {
	my $sqlstatement = "select genres.name, avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			audio=1
			and genres.name is not null
			and tracks_persistent.playCount > 0
		group by genres.name
		order by avgplaycount desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopAverageBitrate {
	my $sqlstatement = "select genres.name,avg(case when bitrate is null then 0 else round(bitrate/16000)*16 end) as avgbitrate from tracks
		join genre_track on
				tracks.id=genre_track.track
		join genres on
				genre_track.genre=genres.id
		where
			genres.name is not null
		group by genres.name
		order by avgbitrate desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- years ---- #

sub getDataTracksByYear {
	my $sqlstatement = "select case when year > 0 then year else 'Unknown' end, count(distinct tracks.id) as nooftracks from tracks
		where
			year is not null
		group by year
		order by year asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostTracks {
	my $sqlstatement = "select year, count(distinct tracks.id) as nooftracks from tracks
		where
			year > 0
			and year is not null
		group by year
		order by nooftracks desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostAlbums {
	my $sqlstatement = "select year, count(distinct tracks.album) as noofalbums from tracks
		where
			year > 0
			and year is not null
			and tracks.album is not null
		group by year
		order by noofalbums desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostRatedTracks {
	my $sqlstatement = "select year, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.rating > 0
		group by year
		order by nooftracks desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithTopRatedTracksAll {
	my $sqlstatement = "select year, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.rating > 0
		group by year
		order by avgrating desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select year, avg(case when tracks_persistent.rating is null then 0 else tracks_persistent.rating/20 end) as avgrating from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.rating > 0
		group by year
		order by avgrating desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracks {
	my $sqlstatement = "select year, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.playCount > 0
		group by year
		order by nooftracks desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracksAverage {
	my $sqlstatement = "select year, avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.playCount > 0
		group by year
		order by avgplaycount desc, year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAverage {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(case when tracks_persistent.playCount is null then 0 else tracks_persistent.playCount end) as avgplaycount from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			year > 0
			and year is not null
			and tracks_persistent.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgplaycount desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByDateAdded {
	my $sqlstatement = "select strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime') as dateadded, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			tracks_persistent.added > 0
			and tracks_persistent.added is not null
		group by strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime')
		order by strftime ('%Y',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%m',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%d',tracks_persistent.added, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

# ---- misc. ---- #

sub getDataAudioFileFormats {
	my $sqlstatement = "select tracks.content_type, count(distinct tracks.id) as nooftypes from tracks
		where
			tracks.audio=1
		group by tracks.content_type
		order by nooftypes desc";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrate {
	my $sqlstatement = "select round(bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks
		where
			audio=1
			and bitrate is not null
			and bitrate > 0
		group by (case
			when round(bitrate/16000)*16 > 1400 then round(bitrate/160000)*160
			when round(bitrate/16000)*16 < 10 then 16
			else round(bitrate/16000)*16
			end)
		order by bitrate asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksBySampleRate {
	my $sqlstatement = "select tracks.samplerate||' Hz',count(distinct tracks.id) from tracks
		where
		tracks.audio = 1
		and tracks.samplerate is not null
		group by tracks.samplerate||' Hz'
		order by tracks.samplerate asc;";

	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrateAudioFileFormat {
	my $dbh = getCurrentDBH();
	my @result = ();
	my @fileFormatsWithBitrate = ();
	my $xLabelTresholds = [[1, 192], [192, 256], [256, 320], [320, 500], [500, 700], [700, 1000], [1000, 1201], [1201, 999999999999]];
	foreach my $xLabelTreshold (@{$xLabelTresholds}) {
		my $minVal = @{$xLabelTreshold}[0];
		my $maxVal = @{$xLabelTreshold}[1];
		my $xLabelName = '';
		if (@{$xLabelTreshold}[0] == 1) {
			$xLabelName = '<'.@{$xLabelTreshold}[1];
		} elsif (@{$xLabelTreshold}[1] == 999999999999) {
			$xLabelName = '>'.(@{$xLabelTreshold}[0]-1);
		} else {
			$xLabelName = @{$xLabelTreshold}[0]."-".((@{$xLabelTreshold}[1])-1);
		}
		my $subData = '';
		my $sqlbitrate = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks
			where
				tracks.audio=1
				and bitrate is not null
				and round(bitrate/10000)*10 >= $minVal
				and round(bitrate/10000)*10 < $maxVal
				and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' AND tracks.content_type != 'dir')
			group by tracks.content_type
			order by tracks.content_type asc";
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

	my $sqlfileformats = "select distinct tracks.content_type from tracks
		where
			tracks.audio=1
			and tracks.remote = 0
			and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' AND tracks.content_type != 'dir')
		group by tracks.content_type
		order by tracks.content_type asc";
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
			my $sqlfileformatsnobitrate = "select count(distinct tracks.id) from tracks
				where tracks.audio=1 and tracks.content_type=\"$fileFormatNoBitrate\"";
			my $sth = $dbh->prepare($sqlfileformatsnobitrate);
			my $fileFormatCount = 0;
			$sth->execute();
			$sth->bind_columns(undef, \$fileFormatCount);
			$sth->fetch();
			$sth->finish();
			$subDataOthers = $subDataOthers.', "'.$fileFormatNoBitrate.'": '.$fileFormatCount;
		}
		$subDataOthers = '{"x": "No bitrate"'.$subDataOthers.'}';
		push(@result, $subDataOthers);
	}

	my @wrapper = (\@result, \@fileFormatsComplete);
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByBitrateAudioFileFormatScatter {
	my $dbh = getCurrentDBH();
	my @result = ();
	my $sqlfileformats = "select distinct tracks.content_type from tracks
		where
			tracks.audio=1
			and bitrate is not null
			and bitrate > 0
			and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' AND tracks.content_type != 'dir')
		group by tracks.content_type
		order by tracks.content_type asc";
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
		my $sqlbitrate = "select round(bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks
		where
			audio=1
			and tracks.remote = 0
			and tracks.content_type=\"$thisFileFormat\"
			and bitrate is not null
			and bitrate > 0
		group by (case
			when round(bitrate/16000)*16 > 1400 then round(bitrate/160000)*160
			when round(bitrate/16000)*16 < 10 then 16
			else round(bitrate/16000)*16
			end)
		order by bitrate asc;";
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
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataListeningTimes {
	my $sqlstatement = "select strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') as timelastplayed, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			tracks_persistent.lastPlayed > 0
			and tracks_persistent.lastPlayed is not null
		group by strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime')
		order by strftime ('%H',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc, strftime('%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataLibStatsText {
	my @result = ();
	my $trackCountSQL = "select count(*) from tracks where audio=1";
	my $trackCount = quickSQLcount($trackCountSQL);
	push (@result, {'name' => 'Total tracks:', 'value' => $trackCount});

	my $trackCountLocalSQL = "select count(*) from tracks where audio=1 and tracks.remote=0";
	my $trackCountLocal = quickSQLcount($trackCountLocalSQL);
	push (@result, {'name' => 'Total local tracks:', 'value' => $trackCountLocal});

	my $trackCountRemoteSQL = "select count(*) from tracks where audio=1 and tracks.remote=1";
	my $trackCountRemote = quickSQLcount($trackCountRemoteSQL);
	push (@result, {'name' => 'Total remote tracks:', 'value' => $trackCountRemote});

	my $totalTimeSQL = "select sum(secs) from tracks where tracks.audio=1";
	my $totalTime = prettifyTime(quickSQLcount($totalTimeSQL));
	push (@result, {'name' => 'Total playing time:', 'value' => $totalTime});

	my $totalLibrarySizeSQL = "select round((sum(filesize)/1024/1024/1024),2)||' GB' from tracks where tracks.audio=1 and tracks.remote=0";
	my $totalLibrarySize = quickSQLcount($totalLibrarySizeSQL);
	push (@result, {'name' => 'Total library size:', 'value' => $totalLibrarySize});

	my $libraryAgeinSecsSQL = "select (strftime('%s', 'now', 'localtime') - min(tracks_persistent.added)) from tracks join tracks_persistent on tracks.url=tracks_persistent.url where tracks.audio=1";
	my $libraryAge = prettifyTime(quickSQLcount($libraryAgeinSecsSQL));
	push (@result, {'name' => 'Libary Age:', 'value' => $libraryAge});

	my $artistCountSQL = "select count(distinct contributors.id) from contributors
	join contributor_track on
		contributor_track.contributor=contributors.id and
		contributor_track.role=1";
	my $artistCount = quickSQLcount($artistCountSQL);
	push (@result, {'name' => 'Artists:', 'value' => $artistCount});

	my $albumArtistCountSQL = "select count(distinct contributors.id) from contributors
	join contributor_track on
		contributor_track.contributor=contributors.id and
		contributor_track.role=5";
	my $albumArtistCount = quickSQLcount($albumArtistCountSQL);
	push (@result, {'name' => 'Album artists:', 'value' => $albumArtistCount});

	my $composerCountSQL = "select count(distinct contributors.id) from contributors
	join contributor_track on
		contributor_track.contributor=contributors.id and
		contributor_track.role=2";
	my $composerCount = quickSQLcount($composerCountSQL);
	push (@result, {'name' => 'Composers:', 'value' => $composerCount});

	my $artistsPlayedSQL = "select count(distinct contributors.id) from contributors
		left join contributor_track on
			contributor_track.contributor=contributors.id and contributor_track.role=1
		left join tracks on
			contributor_track.track=tracks.id
		join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			tracks.audio=1
			and tracks_persistent.playcount>0";
	my $artistsPlayedFloat = quickSQLcount($artistsPlayedSQL)/$artistCount * 100;
	my $artistsPlayedPercentage = sprintf("%.1f", $artistsPlayedFloat).'%';
	push (@result, {'name' => 'Artists played:', 'value' => $artistsPlayedPercentage});

	my $albumsCountSQL = "select count(*) from albums";
	my $albumsCount = quickSQLcount($albumsCountSQL);
	push (@result, {'name' => 'Albums:', 'value' => $albumsCount});

	my $compilationsCountSQL = "select count(*) from albums where compilation=1";
	my $compilationsCountFloat = quickSQLcount($compilationsCountSQL)/$albumsCount * 100;
	my $compilationsCountPercentage = sprintf("%.1f", $compilationsCountFloat).'%';
	push (@result, {'name' => 'Compilations:', 'value' => $compilationsCountPercentage});

	my $artistAlbumsCountSQL = "select count(*) from albums where compilation is null or compilation = 0";
	my $artistAlbumsCount = quickSQLcount($artistAlbumsCountSQL);
	push (@result, {'name' => 'Artist albums:', 'value' => $artistAlbumsCount});

	my $albumsPlayedSQL = "select count(distinct albums.id) from albums
		left join tracks on
			tracks.album=albums.id
		join tracks_persistent on
			tracks.url=tracks_persistent.url
		where
			tracks.audio=1
			and tracks_persistent.playcount>0";
	my $albumsPlayedFloat = quickSQLcount($albumsPlayedSQL)/$albumsCount * 100;
	my $albumsPlayedPercentage = sprintf("%.1f", $albumsPlayedFloat).'%';
	push (@result, {'name' => 'Albums played:', 'value' => $albumsPlayedPercentage});

	my $albumsNoArtworkSQL = "select count(distinct albums.id) from albums where artwork is null";
	my $albumsNoArtwork = quickSQLcount($albumsNoArtworkSQL);
	push (@result, {'name' => 'Albums without artwork:', 'value' => $albumsNoArtwork});

	my $genreCountSQL = "select count(*) from genres";
	my $genreCount = quickSQLcount($genreCountSQL);
	push (@result, {'name' => 'Genres:', 'value' => $genreCount});

	my $losslessTrackCountSQL = "select count(*) from tracks where audio=1 and lossless=1";
	my $losslessTrackCountFloat = quickSQLcount($losslessTrackCountSQL)/$trackCount * 100;
	my $losslessTrackCountPercentage = sprintf("%.1f", $losslessTrackCountFloat).'%';
	push (@result, {'name' => 'Lossless songs:', 'value' => $losslessTrackCountPercentage});

	my $ratedTrackCountSQL = "select count(*) from tracks,tracks_persistent where tracks.url=tracks_persistent.url and audio=1 and rating>0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL);
	my $ratedTrackCountPercentage = sprintf("%.1f", ($ratedTrackCount/$trackCount * 100)).'%';
	push (@result, {'name' => 'Rated songs:', 'value' => $ratedTrackCountPercentage});

	my $songsPlayedOnceSQL = "select count(*) from tracks join tracks_persistent on tracks.url=tracks_persistent.url where audio=1 and tracks_persistent.playcount>0";
	my $songsPlayedOnceFloat = quickSQLcount($songsPlayedOnceSQL)/$trackCount * 100;
	my $songsPlayedOncePercentage = sprintf("%.1f", $songsPlayedOnceFloat).'%';
	push (@result, {'name' => 'Songs played at least once:', 'value' => $songsPlayedOncePercentage});

	my $songsPlayedTotalSQL = "select sum(tracks_persistent.playcount) from tracks join tracks_persistent on tracks.url=tracks_persistent.url where audio=1 and tracks_persistent.playcount>0";
	my $songsPlayedTotal = quickSQLcount($songsPlayedTotalSQL);
	push (@result, {'name' => 'Total play count (incl. repeated):', 'value' => $songsPlayedTotal});

	my $avgTrackLengthSQL = "select strftime('%M:%S', avg(secs)/86400.0) from tracks where tracks.audio=1";
	my $avgTrackLength = quickSQLcount($avgTrackLengthSQL);
	push (@result, {'name' => 'Average track length:', 'value' => $avgTrackLength.' mins'});

	my $avgBitrateSQL = "select round((avg(bitrate)/10000)*10) from tracks where tracks.audio=1";
	my $avgBitrate = quickSQLcount($avgBitrateSQL);
	push (@result, {'name' => 'Average bit rate:', 'value' => $avgBitrate.' kbps'});

	my$avgFileSizeSQL = "select round((avg(filesize)/(1024*1024)), 2)||' MB' from tracks where tracks.audio=1 and tracks.remote=0";
	my $avgFileSize = quickSQLcount($avgFileSizeSQL);
	push (@result, {'name' => 'Average file size:', 'value' => $avgFileSize});

	my $tracksWithLyricsSQL = "select count(distinct tracks.id) from tracks where tracks.audio=1 and tracks.lyrics is not null";
	my $tracksWithLyricsFloat = quickSQLcount($tracksWithLyricsSQL)/$trackCount * 100;
	my $tracksWithLyricsPercentage = sprintf("%.1f", $tracksWithLyricsFloat).'%';
	push (@result, {'name' => 'Tracks with lyrics:', 'value' => $tracksWithLyricsPercentage});

	my $tracksNoReplayGainSQL = "select count(distinct tracks.id) from tracks where tracks.audio=1 and tracks.replay_gain is null";
	my $tracksNoReplayGain = quickSQLcount($tracksNoReplayGainSQL);
	push (@result, {'name' => 'Tracks without replay gain:', 'value' => $tracksNoReplayGain});

	$log->debug(Dumper(\@result));
	return \@result;
}

sub getDataTrackTitleMostFrequentWords {
	my %ignoreCommonWords = ("able" => 1, "about" => 1, "above" => 1, "act" => 1, "adagio" => 1, "after" => 1, "again" => 1, "against" => 1, "ago" => 1, "ain" => 1, "akt" => 1, "album" => 1, "all" => 1, "also" => 1, "alt" => 1, "alternate" => 1, "always" => 1, "among" => 1, "and" => 1, "another" => 1, "any" => 1, "are" => 1, "aria" => 1, "around" => 1, "atto" => 1, "autre" => 1, "away" => 1, "back" => 1, "bad" => 1, "been" => 1, "before" => 1, "behind" => 1, "big" => 1, "black" => 1, "blue" => 1, "bonus" => 1, "but" => 1, "bwv" => 1, "can" => 1, "chanson" => 1, "che" => 1, "come" => 1, "comme" => 1, "con" => 1, "concerto" => 1, "cosa" => 1, "could" => 1, "dans" => 1, "das" => 1, "day" => 1, "del" => 1, "demo" => 1, "dein" => 1, "den" => 1, "der" => 1, "des" => 1, "did" => 1, "die" => 1, "don" => 1, "done" => 1, "down" => 1, "dub" => 1, "dur" => 1, "each" => 1, "edit" => 1, "ein" => 1, "either" => 1, "else" => 1, "est" => 1, "even" => 1, "ever" => 1, "every" => 1, "extended" => 1, "feat" => 1, "featuring" => 1, "first" => 1, "flat" => 1, "for" => 1, "from" => 1, "fur" => 1, "get" => 1, "girl" => 1, "gone" => 1, "gonna" => 1, "good" => 1, "got" => 1, "had" => 1, "has" => 1, "have" => 1, "heart" => 1, "her" => 1, "here" => 1, "him" => 1, "his" => 1, "home" => 1, "how" => 1, "ich" => 1, "iii" => 1, "instrumental" => 1, "interlude" => 1, "intro" => 1, "ist" => 1, "just" => 1, "keep" => 1, "know" => 1, "las" => 1, "les" => 1, "let" => 1, "life" => 1, "like" => 1, "little" => 1, "live" => 1, "long" => 1, "los" => 1, "major" => 1, "make" => 1, "man" => 1, "master" => 1, "may" => 1, "medley" => 1, "mein" => 1, "meu" => 1, "mind" => 1, "mine" => 1, "minor" => 1, "miss" => 1, "mix" => 1, "moderato" => 1, "moi" => 1, "moll" => 1, "molto" => 1, "mon" => 1, "mono" => 1, "more" => 1, "most" => 1, "much" => 1, "music" => 1, "must" => 1, "nao" => 1, "near" => 1, "need" => 1, "never" => 1, "new" => 1, "nicht" => 1, "non" => 1, "not" => 1, "now" => 1, "off" => 1, "old" => 1, "once" => 1, "one" => 1, "only" => 1, "orchestra" => 1, "original" => 1, "ouh" => 1, "our" => 1, "ours" => 1, "out" => 1, "over" => 1, "own" => 1, "part" => 1, "pas" => 1, "piano" => 1, "plus" => 1, "por" => 1, "pour" => 1, "prelude" => 1, "presto" => 1, "quartet" => 1, "que" => 1, "qui" => 1, "quite" => 1, "radio" => 1, "rather" => 1, "recitativo" => 1, "recorded" => 1, "remix" => 1, "right" => 1, "rock" => 1, "roll" => 1, "sao" => 1, "say" => 1, "scene" => 1, "see" => 1, "seem" => 1, "session" => 1, "she" => 1, "side" => 1, "single" => 1, "skit" => 1, "solo" => 1, "some" => 1, "something" => 1, "somos" => 1, "son" => 1, "sonata" => 1, "song" => 1, "sous" => 1, "stereo" => 1, "still" => 1, "street" => 1, "such" => 1, "suite" => 1, "symphony" => 1, "take" => 1, "tel" => 1, "tempo" => 1, "than" => 1, "that" => 1, "the" => 1, "their" => 1, "them" => 1, "then" => 1, "there" => 1, "these" => 1, "they" => 1, "thing" => 1, "think" => 1, "this" => 1, "those" => 1, "though" => 1, "thought" => 1, "three" => 1, "through" => 1, "thus" => 1, "time" => 1, "together" => 1, "too" => 1, "track" => 1, "trio" => 1, "try" => 1, "two" => 1, "una" => 1, "und" => 1, "under" => 1, "une" => 1, "until" => 1, "use" => 1, "version" => 1, "very" => 1, "vivace" => 1, "vocal" => 1, "wanna" => 1, "want" => 1, "was" => 1, "way" => 1, "well" => 1, "went" => 1, "were" => 1, "what" => 1, "when" => 1, "where" => 1, "whether" => 1, "which" => 1, "while" => 1, "who" => 1, "whose" => 1, "why" => 1, "will" => 1, "with" => 1, "world" => 1, "yet" => 1, "you" => 1, "your" => 1);
	my $dbh = getCurrentDBH();
	my $sqlstatement = "select tracks.titlesearch from tracks
		where
			tracks.titlesearch is not null
			and length(tracks.titlesearch) > 2
			and tracks.audio = 1
		group by tracks.titlesearch
		order by tracks.titlesearch asc;";
	my $thisTitle;
	my %frequentwords;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisTitle);
	while ($sth->fetch()) {
		my @words = split /\W+/, $thisTitle; #skip non-word characters
		foreach my $word(@words){
			chomp $word;
			$word = lc $word;
			$word =~ s/^\s+|\s+$//g; #remove beginning/trailing whitespace
			if ((length $word < 3) || $ignoreCommonWords{$word}) {next;}
			my $key = $word;
			if (exists $frequentwords{$key}) {
				$frequentwords{$key}++;
			} else {
				$frequentwords{$key} = 1;
			}
		}
	}

	my $itemCount = 0;
	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or "\F$b" cmp "\F$a"} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
		$itemCount++;
 		if ($itemCount == 50) {last;}
	};

	$log->debug(Dumper(\@keys));
	return \@keys;
}

#####################
# helpers

sub executeSQLstatement {
	my @result = ();
	my $dbh = getCurrentDBH();
	my $sqlstatement = shift;
	my $numberValuesToBind = shift || 2;
	#eval {
		my $sth = $dbh->prepare($sqlstatement);
		$sth->execute() or do {
			$sqlstatement = undef;
		};
		my $xAxisDataItem; # string values
		my $yAxisDataItem; # numeric values
		if ($numberValuesToBind == 3) {
			my $labelExtraDataItem; # extra data for chart labels
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem, \$labelExtraDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem); utf8::decode($labelExtraDataItem);
				push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem, 'labelExtra' => $labelExtraDataItem}) unless ($yAxisDataItem == 0);
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
	$log->debug('SQL result = '.Dumper(\@result));
	$log->debug('Got '.scalar(@result).' items');
	return \@result;
}

sub quickSQLcount {
	my $dbh = getCurrentDBH();
	my $sqlstatement = shift;
	my $thisCount;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisCount);
	$sth->fetch();
	return $thisCount;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub prettifyTime {
	my $timeinseconds = shift;
	my $seconds = (int($timeinseconds)) % 60;
	my $minutes = (int($timeinseconds / (60))) % 60;
	my $hours = (int($timeinseconds / (60*60))) % 24;
	my $days = (int($timeinseconds / (60*60*24))) % 7;
	my $weeks = (int($timeinseconds / (60*60*24*7))) % 52;
	my $years = (int($timeinseconds / (60*60*24*365))) % 10;
	my $prettyTime = (($years > 0 ? $years." years  " : '').($weeks > 0 ? $weeks." weeks  " : '').($days > 0 ? $days." days  " : '').($hours > 0 ? $hours." hours  " : '').($minutes > 0 ? $minutes." minutes" : ''));
	return $prettyTime;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
