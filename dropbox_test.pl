#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use autodie;

use WebService::Dropbox;
use Data::Dumper;
use IO::File;
use MySQL::Backup;
use File::Temp;
use IO::Compress::Gzip qw/ gzip /;
use Config::Simple;

unless ($ARGV[0]) {
	die "Usage: $0 <db_name>\n";
}

my %Config;
Config::Simple->import_from('dropbox.cfg', \%Config) or warn "Unable to load config! We will attempt to run the setup now.\n";

my $dropbox_key    = 'nfn62hdrw0l47k6';
my $dropbox_secret = 'r6hcfhcog5nd653';

my $access_token = $Config{'dropbox.access_token'} || '';
my $access_secret = $Config{'dropbox.access_secret'} || '';

my $date = get_time();

my $logging = 1;
my $debug   = 0;

my $db_to_backup = $ARGV[0];

my $mb = new MySQL::Backup($db_to_backup,'127.0.0.1','root','',{'USE_REPLACE' => 1, 'SHOW_TABLE_NAMES' => 1});

my $dropbox = WebService::Dropbox->new({
	key    => $dropbox_key,
	secret => $dropbox_secret
});

sub get_time {
	my @date = localtime;
	$date[3] = 0 . $date[3] unless $date[3] > 9;
	$date[4] = 0 . $date[4] unless $date[4] > 9;
	my $test = ($date[3]).($date[4]++).($date[5]-100);
	return $test;
}

if (!$access_token or !$access_secret) {
	my $url = $dropbox->login or die $dropbox->error;
	warn "Please Access URL and press Enter: $url\n";
	<STDIN>;
	$dropbox->auth or die $dropbox->error;
	warn "access_token: " . $dropbox->access_token . "\n";
	warn "access_secret: " . $dropbox->access_secret . "\n";

	my $cfg = new Config::Simple(syntax=>'ini');
	$cfg->param("dropbox.access_token" => $dropbox->access_token);
	$cfg->param("dropbox.access_secret" => $dropbox->access_secret);
	$cfg->write("dropbox.cfg");
} else {
	$dropbox->access_token($access_token);
	$dropbox->access_secret($access_secret);
}

my $info = $dropbox->account_info or die $dropbox->error;

say "** Connected to Dropbox as $info->{'display_name'} **" if $logging;

print Dumper $info if $debug;

$dropbox->root('sandbox');

say "** Generating MySQL backup now of databse ($db_to_backup) **" if $logging;

my $sql_fh = IO::File->new('temp_file', '>') or die $!;
print $sql_fh $mb->create_structure();
print $sql_fh $mb->data_backup();
$sql_fh->close;

my $gzip = gzip 'temp_file' => 'temp_file.gz' or die $!;

my $fh = IO::File->new('temp_file.gz') or die $!;
my $upload_name = "$db_to_backup-$date.sql.gz";

my $upload = $dropbox->files_put($upload_name, $fh) or die $dropbox->error;
$fh->close;
print Dumper $upload if $debug;

say "** File ($upload->{'path'}) has been uploaded to Dropbox **" if $logging;

unlink 'temp_file';
unlink 'temp_file.gz';

