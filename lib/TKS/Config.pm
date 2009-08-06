# Copyright (C) 2009 Catalyst IT Ltd (http://www.catalyst.net.nz)
#
# This file is distributed under the same terms as tks itself.
package TKS::Config;

use strict;
use warnings;
use Exporter 'import';
use Config::IniFiles;
use File::Slurp;
use JSON qw(encode_json decode_json);

our @EXPORT = qw(config);
our @EXPORT_OK = qw(config_set config_delete);

my $config;
my $config_store;
my $reverse_request_map;
my $store_filename;

sub config {
    my ($section, $key) = @_;

    return unless $section;

    return $reverse_request_map->{$key} if $section eq 'reverserequestmap';

    return $config_store->{$section}{$key} || $config->val($section, $key);
};

sub config_set {
    my ($section, $key, $value) = @_;

    my $existing_value = config($section, $key);

    if ( not defined $existing_value or $existing_value ne $value ) {
        $config_store->{$section}{$key} = $value;
        write_store();
    }
}

sub config_delete {
    my ($section, $key) = @_;

    delete $config_store->{$section}{$key};
    write_store();
}

sub write_store {
    write_file($store_filename, encode_json($config_store));
}

BEGIN {
    $store_filename = "$ENV{HOME}/.cache/tksinfo";
    mkdir "$ENV{HOME}/.cache" unless -d "$ENV{HOME}/.cache";

    my $file;
    foreach my $potential_file ( $ENV{TKS_RC}, "$ENV{HOME}/.config/tks", "$ENV{HOME}/.tksrc" ) {
        next unless $potential_file;
        if ( -r $potential_file ) {
            $file = $potential_file;
            last;
        }
    }

    if ( $file ) {
        my $data = read_file($file);
        if ( $data =~ s{ ^ \[ wrmap \] }{[requestmap]}xms ) {
            print "------------------------------------------------------------------------------\n";
            print "WARNING: Your config file $file has been altered\n\n";
            print "The [wrmap] section has been renamed to [requestmap] to operate correctly with\n";
            print "the new version of TKS\n\n";
            print "Please run tks again with exactly the same arguments to continue your\noperation\n";
            print "------------------------------------------------------------------------------\n";
            write_file($file, $data);
            exit 0;
        }
    }

    if ( $file ) {
        $config = Config::IniFiles->new( -file => $file );
    }
    else {
        $config = Config::IniFiles->new();
    }

    foreach my $key ( $config->Parameters('requestmap') ) {
        my $value = $config->val('requestmap', $key);
        if ( ref $value or $value =~ /\n/ ) {
            die "[requestmap] entry '$key' has multiple mappings in $file\n";
        }
        $reverse_request_map->{$value} = $key;
        if ( $value =~ s{ \A \s* (.*?) \s* \z }{$1}xms ) {
            $config->setval('requestmap', $key, $value);
        }
    }

    $config_store = {};
    if ( -f $store_filename ) {
        $config_store = decode_json(read_file($store_filename));
    }
};

1;
