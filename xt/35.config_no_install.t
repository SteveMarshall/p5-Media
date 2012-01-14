#!/usr/bin/env perl

use Modern::Perl;
use Capture::Tiny   qw( capture );
use Cwd;
use File::Copy;
use File::Path;
use IO::All;
use Media;
use Test::More;


my $input_file = "$ENV{'MEDIA_TESTING'}/ac3.vob";
my $cwd        = getcwd();

if ( !-f $input_file ) {
    plan skip_all => "${input_file} file is missing";
    exit;
}

plan tests => 19;

# ensure a clean directory structure
my $result = system 'rm -rf xt/encode xt/movies xt/queue xt/trash';
die "'rm -rf xt/encode xt/movies xt/queue xt/trash': $!"
    if $result >> 8;


my $media       = Media->new( 't/conf/trash.conf' );
my $source      = 'xt/source/flibble';
my $config_file = "$source/media.conf";
mkpath $source;
copy( $input_file, $source )
    or die;

my $handler = $media->get_empty_handler( undef, 'VideoFile' );
$handler->create_config_file( $source );

# update config file means queue should occur
my $barbarella_conf < io 'xt/conf/barbarella_no_install.conf';
$barbarella_conf > io $config_file;
my $created_config < io $config_file;
is( $barbarella_conf, $created_config, 'config updated properly' );

$media->queue_media( $source );
ok( $media->queue_count() == 1, 'queue created' );

# infinite wait without the queue job
die unless $media->queue_count() == 1;

my( $job, $payload ) = $media->next_queue_job();
isa_ok( $job, 'IPC::DirQueue::Job' );
is_deeply(
        $payload,
        {
            details => {
                audio   => '1:stereo:English',
                feature => '1',
                install => '0',
                rating  => 'X',
                title   => 'Barbarella',
                year    => '1968',
            },
            input   => {
                media_conf => "$cwd/t/conf/trash.conf",
                config     => "$source/media.conf",
                file       => "$source/ac3.vob",
                poster     => 'http://bumph.cackhanded.net/poster.png',
                title      => '1',
            },
            medium  => 'VideoFile',
            name    => 'Barbarella - X (1968)',
            type    => 'Movie',
        }
    );

$media->encode_media( $payload );

my $encode_directory = 'xt/encode/Barbarella - X (1968)';
my $encoded_file     = "$encode_directory/Z-converted.m4v";
my $target_file      = 'xt/movies/All/Barbarella - X (1968)/'
                     . 'Barbarella - X (1968).m4v';

ok( !-f $target_file, 'file installed' );
exit if -f $target_file;

ok( -d $encode_directory,
    'encoder has not cleared up after itself' );
ok( ! -f 'xt/trash/ac3.vob',
    'encoder has not trashed source file' );
ok( ! -f 'xt/trash/flibble-media.conf',
    'encoder has not trashed media.conf' );
ok( -d $source, 
    'encoder has not cleared up source directories' );


$handler = $media->get_empty_handler( 'Movie', 'VideoFile' );
my %metadata = $handler->extract_metadata( $encoded_file );
is_deeply(
        \%metadata,
        {},
        'metadata has not been added'
    );

my @tracks = $handler->extract_tracks( $encoded_file );
is_deeply(
        \@tracks,
        [
            {
                kind => "avc1",
                type => "vide",
            },
            {
                kind => "mp4a",
                type => "soun",
            }
        ],
        'correct tracks exist'
    );


# reset this to make sure nothing is cached from before
my $installer = Media->new( 't/conf/trash.conf' );
$installer->install_converted_media( $encode_directory );

ok( -f $target_file, 'file installed' );
exit unless -f $target_file;

ok( !-d $encode_directory,
    'installer has cleared up after itself' );
ok( -f 'xt/trash/ac3.vob',
    'installer has trashed source file' );
ok( -f 'xt/trash/flibble-media.conf',
    'installer has trashed media.conf' );
ok( !-d $source, 
    'installer has cleared up source directories' );

%metadata = $handler->extract_metadata( $target_file );
is_deeply(
        \%metadata,
        {
            artwork_count => '1',
            kind          => 'Movie',
            rating        => 'X',
            title         => 'Barbarella',
            year          => '1968',
        },
        'metadata has now been added'
    );

@tracks = $handler->extract_tracks( $target_file );
is_deeply(
        \@tracks,
        [
            {
                kind => "avc1",
                type => "vide",
            },
            {
                kind => "mp4a",
                type => "soun",
            }
        ],
        'correct tracks exist'
    );


my $handbrake_output = $handler->scan_input( 0, $target_file );
my %titles           = $handler->analyse_input( $handbrake_output );
is_deeply(
        \%titles,
        {
            handbrake_version => "0.9.5",
            input_type        => "mov",
            1                 => {
                audio     => [
                    {
                        channels => '2.0 ch',
                        code     => 'und',
                        format   => 'AAC',
                        language => 'Unknown',
                        track    => '1',
                    },
                ],
                crop      => '0/0/0/0',
                duration  => '00:01:08',
                size      => '720x576, pixel aspect: 2048/1435, display '
                           . 'aspect: 1.78, 25.000 fps',
                subtitles => [],
            },
        },
        'movie appears to have been encoded correctly',
    );
