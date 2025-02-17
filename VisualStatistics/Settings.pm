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

package Plugins::VisualStatistics::Settings;

use strict;
use warnings;
use utf8;

use base qw(Slim::Web::Settings);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.visualstatistics');
my $log = logger('plugin.visualstatistics');
my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_VISUALSTATISTICS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/VisualStatistics/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(usefullscreen displayapcdupes minartisttracks minalbumtracks clickablebars savetoplmaxtracks savetoploverwrite));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	$paramRef->{'apcenabled'} = 1 if $apc_enabled;
}

1;
