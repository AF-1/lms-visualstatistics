#
# Visual Statistics
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
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
