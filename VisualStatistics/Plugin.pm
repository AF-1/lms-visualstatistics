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

	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks,tracks_persistent where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
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
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from contributors
		join contributor_track on
			contributor_track.contributor = contributors.id and contributor_track.role in (1,5,6)
		join tracks on
			tracks.id = contributor_track.track
		join albums on
			albums.id = tracks.album
		where
			contributors.id is not null
			and contributors.name is not '$VAstring'
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by contributors.name
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostAlbums {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct albums.id) as noofalbums from albums
		join contributors on
			contributors.id = albums.contributor
		join contributor_track on
			contributor_track.contributor = albums.contributor and contributor_track.role in (1,5)
		where
			compilation is not 1
			and contributors.name is not '$VAstring'
		group by contributors.name
		order by noofalbums desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostRatedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and tracks_persistent.rating > 0
		group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTopRatedTracksAll {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
		group by tracks.primary_artist
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTopRatedTracksRatedOnly {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and tracks_persistent.rating > 0
		group by tracks.primary_artist
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and tracks_persistent.playCount > 0
		group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracksAverage {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
		group by tracks.primary_artist
		order by avgplaycount desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsRatingPlaycount {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select t.* from (select avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
		group by tracks.primary_artist) as t
		where (t.avgplaycount >= 0.05 and t.avgrating >= 0.05);";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- albums ---- #

sub getDataAlbumsByYear {
	my $sqlstatement = "select case when albums.year > 0 then albums.year else 'Unknown' end, count(distinct albums.id) as noofalbums from albums
		join tracks on
			tracks.album = albums.id
		where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.year
		order by albums.year asc";
	return executeSQLstatement($sqlstatement);
}

sub getDataAlbumsWithMostTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostRatedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTopRatedTracksAll {
	my $sqlstatement = "select albums.title, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select albums.title, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by albums.title
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracksAverage {
	my $sqlstatement = "select albums.title, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount, contributors.name from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by avgplaycount desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- genres ---- #

sub getDataGenresWithMostTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostAlbums {
	my $sqlstatement = "select genres.name, count(distinct albums.id) as noofalbums from albums
		join tracks on
			tracks.album = albums.id
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by noofalbums desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostRatedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopRatedTracksAll {
	my $sqlstatement = "select genres.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgrating desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select genres.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by genres.name
		order by avgrating desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracksAverage {
	my $sqlstatement = "select genres.name, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by genres.name
		order by avgplaycount desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopAverageBitrate {
	my $sqlstatement = "select genres.name, avg(round(ifnull(tracks.bitrate,0)/16000)*16) as avgbitrate from tracks
		join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			genres.name is not null
			and	tracks.audio = 1
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgbitrate desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- years ---- #

sub getDataTracksByYear {
	my $sqlstatement = "select case when tracks.year > 0 then tracks.year else 'Unknown' end, count(distinct tracks.id) as nooftracks from tracks
		where
			tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by tracks.year asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostAlbums {
	my $sqlstatement = "select year, count(distinct tracks.album) as noofalbums from tracks
		where
			tracks.year > 0
			and tracks.year is not null
			and tracks.album is not null
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and	(tracks.audio = 1 or tracks.extid is not null)
		group by year
		order by noofalbums desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostRatedTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithTopRatedTracksAll {
	my $sqlstatement = "select tracks.year, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by avgrating desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithTopRatedTracksRatedOnly {
	my $sqlstatement = "select tracks.year, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by tracks.year
		order by avgrating desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracksAverage {
	my $sqlstatement = "select year, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by tracks.year
		order by avgplaycount desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAverage {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and	(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgplaycount desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByDateAdded {
	my $sqlstatement = "select strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime') as dateadded, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
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
			tracks.audio = 1
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.content_type
		order by nooftypes desc";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrate {
	my $sqlstatement = "select round(bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks
		where
			tracks.audio = 1
			and tracks.bitrate is not null
			and tracks.bitrate > 0
		group by (case
			when round(tracks.bitrate/16000)*16 > 1400 then round(tracks.bitrate/160000)*160
			when round(tracks.bitrate/16000)*16 < 10 then 16
			else round(tracks.bitrate/16000)*16
			end)
		order by tracks.bitrate asc;";
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
				tracks.audio = 1
				and tracks.bitrate is not null
				and round(tracks.bitrate/10000)*10 >= $minVal
				and round(tracks.bitrate/10000)*10 < $maxVal
				and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
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
			tracks.audio = 1
			and tracks.remote = 0
			and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
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
				where tracks.audio = 1 and tracks.content_type=\"$fileFormatNoBitrate\"";
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
			tracks.audio = 1
			and tracks.bitrate is not null
			and tracks.bitrate > 0
			and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
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
		my $sqlbitrate = "select round(tracks.bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks
		where
			tracks.audio = 1
			and tracks.remote = 0
			and tracks.content_type=\"$thisFileFormat\"
			and tracks.bitrate is not null
			and tracks.bitrate > 0
		group by (case
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
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataListeningTimes {
	my $sqlstatement = "select strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') as timelastplayed, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks_persistent.lastPlayed > 0
			and tracks_persistent.lastPlayed is not null
		group by strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime')
		order by strftime ('%H',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc, strftime('%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataLibStatsText {
	my @result = ();
	my $trackCountSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCount = quickSQLcount($trackCountSQL);
	push (@result, {'name' => 'Total tracks:', 'value' => $trackCount});

	my $trackCountLocalSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.remote = 0 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountLocal = quickSQLcount($trackCountLocalSQL);
	push (@result, {'name' => 'Total local tracks:', 'value' => $trackCountLocal});

	my $trackCountRemoteSQL = "select count(distinct tracks.id) from tracks where tracks.audio =1 and tracks.remote = 1 and tracks.extid is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountRemote = quickSQLcount($trackCountRemoteSQL);
	push (@result, {'name' => 'Total remote tracks:', 'value' => $trackCountRemote});

	my $totalTimeSQL = "select sum(secs) from tracks where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $totalTime = prettifyTime(quickSQLcount($totalTimeSQL));
	push (@result, {'name' => 'Total playing time:', 'value' => $totalTime});

	my $totalLibrarySizeSQL = "select round((sum(filesize)/1024/1024/1024),2)||' GB' from tracks where tracks.audio = 1 and tracks.remote = 0 and tracks.filesize is not null";
	my $totalLibrarySize = quickSQLcount($totalLibrarySizeSQL);
	push (@result, {'name' => 'Total library size:', 'value' => $totalLibrarySize});

	my $libraryAgeinSecsSQL = "select (strftime('%s', 'now', 'localtime') - min(tracks_persistent.added)) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.audio = 1";
	my $libraryAge = prettifyTime(quickSQLcount($libraryAgeinSecsSQL));
	push (@result, {'name' => 'Library Age:', 'value' => $libraryAge});

	my $artistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track where contributor_track.role in (1,5,6)";
	my $artistCount = quickSQLcount($artistCountSQL);
	push (@result, {'name' => 'Artists:', 'value' => $artistCount});

	my $albumArtistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track where contributor_track.role = 5";
	my $albumArtistCount = quickSQLcount($albumArtistCountSQL);
	push (@result, {'name' => 'Album artists:', 'value' => $albumArtistCount});

	my $composerCountSQL = "select count(distinct contributor_track.contributor) from contributor_track where contributor_track.role = 2";
	my $composerCount = quickSQLcount($composerCountSQL);
	push (@result, {'name' => 'Composers:', 'value' => $composerCount});

	my $artistsPlayedSQL = "select count(distinct contributor_track.contributor) from contributor_track
		join tracks on
			tracks.id = contributor_track.track
		join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5 and tracks_persistent.playcount > 0
		where
			tracks.audio = 1
			and contributor_track.role in (1,5,6)";
	my $artistsPlayedFloat = quickSQLcount($artistsPlayedSQL)/$artistCount * 100;
	my $artistsPlayedPercentage = sprintf("%.1f", $artistsPlayedFloat).'%';
	push (@result, {'name' => 'Artists played:', 'value' => $artistsPlayedPercentage});

	my $albumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id where tracks.audio = 1";
	my $albumsCount = quickSQLcount($albumsCountSQL);
	push (@result, {'name' => 'Albums:', 'value' => $albumsCount});

	my $compilationsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id where tracks.audio = 1 and albums.compilation = 1";
	my $compilationsCountFloat = quickSQLcount($compilationsCountSQL)/$albumsCount * 100;
	my $compilationsCountPercentage = sprintf("%.1f", $compilationsCountFloat).'%';
	push (@result, {'name' => 'Compilations:', 'value' => $compilationsCountPercentage});

	my $artistAlbumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id where tracks.audio = 1 and (albums.compilation is null or albums.compilation = 0)";
	my $artistAlbumsCount = quickSQLcount($artistAlbumsCountSQL);
	push (@result, {'name' => 'Artist albums:', 'value' => $artistAlbumsCount});

	my $albumsPlayedSQL = "select count(distinct albums.id) from albums
		join tracks on
			tracks.album = albums.id
		join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.audio = 1
			and tracks_persistent.playcount > 0";
	my $albumsPlayedFloat = quickSQLcount($albumsPlayedSQL)/$albumsCount * 100;
	my $albumsPlayedPercentage = sprintf("%.1f", $albumsPlayedFloat).'%';
	push (@result, {'name' => 'Albums played:', 'value' => $albumsPlayedPercentage});

	my $albumsNoArtworkSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id where tracks.audio = 1 and albums.artwork is null";
	my $albumsNoArtwork = quickSQLcount($albumsNoArtworkSQL);
	push (@result, {'name' => 'Albums without artwork:', 'value' => $albumsNoArtwork});

	my $genreCountSQL = "select count(distinct genres.id) from genres";
	my $genreCount = quickSQLcount($genreCountSQL);
	push (@result, {'name' => 'Genres:', 'value' => $genreCount});

	my $losslessTrackCountSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.lossless = 1";
	my $losslessTrackCountFloat = quickSQLcount($losslessTrackCountSQL)/$trackCount * 100;
	my $losslessTrackCountPercentage = sprintf("%.1f", $losslessTrackCountFloat).'%';
	push (@result, {'name' => 'Lossless songs:', 'value' => $losslessTrackCountPercentage});

	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks, tracks_persistent where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL);
	my $ratedTrackCountPercentage = sprintf("%.1f", ($ratedTrackCount/$trackCount * 100)).'%';
	push (@result, {'name' => 'Rated songs:', 'value' => $ratedTrackCountPercentage});

	my $songsPlayedOnceSQL = "select count(distinct tracks.id) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedOnceFloat = quickSQLcount($songsPlayedOnceSQL)/$trackCount * 100;
	my $songsPlayedOncePercentage = sprintf("%.1f", $songsPlayedOnceFloat).'%';
	push (@result, {'name' => 'Songs played at least once:', 'value' => $songsPlayedOncePercentage});

	my $songsPlayedTotalSQL = "select sum(tracks_persistent.playcount) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedTotal = quickSQLcount($songsPlayedTotalSQL);
	push (@result, {'name' => 'Total play count (incl. repeated):', 'value' => $songsPlayedTotal});

	my $avgTrackLengthSQL = "select strftime('%M:%S', avg(secs)/86400.0) from tracks where tracks.audio = 1";
	my $avgTrackLength = quickSQLcount($avgTrackLengthSQL);
	push (@result, {'name' => 'Average track length:', 'value' => $avgTrackLength.' mins'});

	my $avgBitrateSQL = "select round((avg(bitrate)/10000)*10) from tracks where tracks.audio = 1 and tracks.bitrate is not null";
	my $avgBitrate = quickSQLcount($avgBitrateSQL);
	push (@result, {'name' => 'Average bit rate:', 'value' => $avgBitrate.' kbps'});

	my$avgFileSizeSQL = "select round((avg(filesize)/(1024*1024)), 2)||' MB' from tracks where tracks.audio = 1 and tracks.remote=0 and tracks.filesize is not null";
	my $avgFileSize = quickSQLcount($avgFileSizeSQL);
	push (@result, {'name' => 'Average file size:', 'value' => $avgFileSize});

	my $tracksWithLyricsSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.lyrics is not null";
	my $tracksWithLyricsFloat = quickSQLcount($tracksWithLyricsSQL)/$trackCount * 100;
	my $tracksWithLyricsPercentage = sprintf("%.1f", $tracksWithLyricsFloat).'%';
	push (@result, {'name' => 'Tracks with lyrics:', 'value' => $tracksWithLyricsPercentage});

	my $tracksNoReplayGainSQL = "select count(distinct tracks.id) from tracks where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_gain is null";
	my $tracksNoReplayGain = quickSQLcount($tracksNoReplayGainSQL);
	push (@result, {'name' => 'Tracks without replay gain:', 'value' => $tracksNoReplayGain});

	$log->debug(Dumper(\@result));
	return \@result;
}

sub getDataTrackTitleMostFrequentWords {
	my %ignoreCommonWords = map {
		$_ => 1
	} ("able", "about", "above", "acoustic", "act", "adagio", "after", "again", "against", "ago", "ain", "air", "akt", "album", "all", "allegretto", "allegro", "also", "alt", "alternate", "always", "among", "and", "andante", "another", "any", "are", "aria", "around", "atto", "autre", "away", "back", "bad", "beat", "been", "before", "behind", "big", "black", "blue", "bonus", "but", "bwv", "can", "chanson", "che", "club", "come", "comme", "con", "concerto", "cosa", "could", "dans", "das", "day", "days", "dein", "del", "demo", "den", "der", "des", "did", "die", "don", "done", "down", "dub", "dur", "each", "edit", "ein", "either", "else", "end", "est", "even", "ever", "every", "everything", "extended", "feat", "featuring", "first", "flat", "for", "from", "fur", "get", "girl", "going", "gone", "gonna", "good", "got", "gotta", "had", "has", "have", "heart", "her", "here", "hey", "him", "his", "home", "how", "ich", "iii", "instrumental", "interlude", "intro", "ist", "just", "keep", "know", "las", "last", "les", "let", "life", "like", "little", "live", "long", "los", "major", "make", "man", "master", "may", "medley", "mein", "meu", "mind", "mine", "minor", "miss", "mix", "moderato", "moi", "moll", "molto", "mon", "mono", "more", "most", "much", "music", "must", "nao", "near", "need", "never", "new", "nicht", "nobody", "non", "not", "nothing", "now", "off", "old", "once", "one", "only", "orchestra", "original", "ouh", "our", "ours", "out", "over", "own", "part", "pas", "piano", "please", "plus", "por", "pour", "prelude", "presto", "quartet", "que", "qui", "quite", "radio", "rather", "recitativo", "recorded", "remix", "right", "rock", "roll", "sao", "say", "scene", "see", "seem", "session", "she", "side", "single", "skit", "solo", "some", "something", "somos", "son", "sonata", "song", "sous", "stereo", "still", "street", "such", "suite", "symphony", "szene", "take", "teil", "tel", "tempo", "than", "that", "the", "their", "them", "then", "there", "these", "they", "thing", "think", "this", "those", "though", "thought", "three", "through", "thus", "time", "titel", "together", "too", "track", "trio", "try", "two", "una", "und", "under", "une", "until", "use", "version", "very", "vivace", "vocal", "wanna", "want", "was", "way", "well", "went", "were", "what", "when", "where", "whether", "which", "while", "who", "whose", "why", "will", "with", "without", "woo", "world", "yet", "you", "your");

	my $dbh = getCurrentDBH();
	my $sqlstatement = "select tracks.titlesearch from tracks
		where
			length(tracks.titlesearch) > 2
			and tracks.audio = 1
		group by tracks.titlesearch";
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
			if ((length $word < 3) || $ignoreCommonWords{$word}) {next;}
			$frequentwords{$word} ||= 0;
			$frequentwords{$word}++;
		}
	}

	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or "\F$a" cmp "\F$b"} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
 		last if scalar @keys >= 50;
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
