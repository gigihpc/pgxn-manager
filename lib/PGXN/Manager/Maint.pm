package PGXN::Manager::Maint;

use 5.12.0;
use utf8;
use Moose;
use PGXN::Manager;
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Carp;
use namespace::autoclean;

my $TMPDIR = PGXN::Manager->new->config->{tmpdir}
          || File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
make_path $TMPDIR if !-d $TMPDIR;

has verbosity => (is => 'rw', required => 1, isa => 'Int', default => 0);
has workdir  => (is => 'rw', required => 0, isa => 'Str', default => sub {
    File::Spec->catdir($TMPDIR, "working.$$")
});

sub go {
    my $class = shift;
    $class->new( $class->_config )->run(@ARGV);
}

sub run {
    my ($self, $command) = (shift, shift);
    my $meth = $self->can($command)
        or croak qq{PGXN Maint: "$command" is not a command};
    $self->$meth(@_);
}

sub update_stats {
    my $self = shift;
    my $pgxn = PGXN::Manager->instance;
    my $tmpl = $pgxn->uri_templates->{stats};
    my $dir  = File::Spec->catdir($self->workdir, 'dest');
    my $root = PGXN::Manager->instance->config->{mirror_root};
    my %files;
    make_path $dir;

    $pgxn->conn->run(sub {
        my $sth = $_->prepare('SELECT * FROM all_stats_json()');
        $sth->execute;
        $sth->bind_columns(\my ($stat_name, $json));

        while ($sth->fetch) {
            my $uri = $tmpl->process( stats => $stat_name );
            my $fn  = File::Spec->catfile($dir, $uri->path_segments);
            $self->_write_json_to($json, $fn);
            $files{$fn} = File::Spec->catfile($root, $uri->path_segments);
        }
    });

    # Move all the other files over.
    while (my ($src, $dest) = each %files) {
        PGXN::Manager->move_file($src, $dest);
    }

    return $self;
}

sub _write_json_to {
    my ($self, $json, $fn) = @_;
    make_path dirname $fn;
    open my $fh, '>', $fn or die "Cannot open $fn: $!\n";
    print $fh $json;
    close $fh or die "Cannot close $fn: $!\n";
}

sub DEMOLISH {
    my $self = shift;
    if (my $path = $self->workdir) {
        remove_tree $path if -e $path;
    }
}

sub _pod2usage {
    shift;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => __FILE__,
        @_
    );
}

sub _config {
    my $self = shift;
    require Getopt::Long;
    Getopt::Long::Configure( qw(bundling) );

    my %opts = (
        verbosity => 0,
    );

    Getopt::Long::GetOptions(
        'verbose|V+'         => \$opts{verbosity},
        'help|h'             => \$opts{help},
        'man|M'              => \$opts{man},
        'version|v'          => \$opts{version},
    ) or $self->_pod2usage;

    # Handle documentation requests.
    $self->_pod2usage(
        ( $opts{man} ? ( '-sections' => '.+' ) : ()),
        '-exitval' => 0,
    ) if $opts{help} or $opts{man};

    # Handle version request.
    if ($opts{version}) {
        require File::Basename;
        print File::Basename::basename($0), ' (', __PACKAGE__, ') ',
            __PACKAGE__->VERSION, $/;
        exit;
    }

    return %opts;
}

1;
__END__

=head1 Name

PGXN::Manager::Maint - PGXN Manager maintenance utility

=head1 Synopsis

  use PGXN::Manager::Maint;
  PGXN::Manager::Maint->go;

=head1 Description

This module provides the implementation for for C<pgxn_maint>, though it may
of course be used programmatically as a library. To use it, simply instantiate
it and call one of its maintenance methods. Or use it from L<pgxn_maint> on
the command-line for easy maintenance of your database and mirror.

Periodically, things come up where you need to do a maintenance task. Perhaps
a new version of PGXN::Manager provides new JSON keys in a stats file, or adds
new metadata to a distribution F<META.json> file. Use PGXN::Manager::Maint to
regenerate the needed files, or to reindex existing distributions so that
their metadata will be updated.

=head1 Class Interface

=head2 Constructor

=head3 C<new>

  my $maint = PGXN::Manager::Maint->new(%params);

Creates and returns a new PGXN::Manager::Maint object. The supported parameters
are:

=over

=item C<verbosity>

An incremental integer specifying the level of verbosity to use during a sync.
By default, PGXN::Manager::Maint runs in quiet mode, where only errors are emitted
to C<STDERR>.

=back

=head2 Class Method

=head3 C<go>

  PGXN::Manager::Maint->go;

Called by L<pgxn_maint>. It simply parses C<@ARGV> for options and passes
those appropriate to C<new>. It then calls C<run()> and passes the remaining
values in C<@ARGV>. It thus makes the L<pgxn_maint> interface possible.

=head1 Instance Interface

=head2 Instance Methods

=head3 C<run>

  $maint->run($task, @args);

Runs a maintenance task. Pass in any additional arguments required of the
task. Useful if you don't know in advance what the task will be; otherwise you
could just call the appropriate task method directly.

=head3 C<update_stats>

  $maint->update_stats;

Updates all the system-wide stats files from the database. The stats files are
JSON and their location is defined by the C<stats> URI template in the PGXN
Manager configuration file. Currently, they include:

=over

=item F<dist.json>

=item F<extension.json>

=item F<user.json>

=item F<tag.json>

=item F<summary.json>

=back

=head2 Instance Accessors

=head3 C<verbosity>

  my $verbosity = $maint->verbosity;
  $maint->verbosity($verbosity);

Get or set an incremental verbosity. The higher the integer specified, the
more verbosity the sync.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2011 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|http://www.opensource.org/licenses/postgresql>.

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose, without fee, and without a written agreement is
hereby granted, provided that the above copyright notice and this paragraph
and the following two paragraphs appear in all copies.

In no event shall David E. Wheeler be liable to any party for direct,
indirect, special, incidental, or consequential damages, including lost
profits, arising out of the use of this software and its documentation, even
if David E. Wheeler has been advised of the possibility of such damage.

David E. Wheeler specifically disclaims any warranties, including, but not
limited to, the implied warranties of merchantability and fitness for a
particular purpose. The software provided hereunder is on an "as is" basis,
and David E. Wheeler has no obligations to provide maintenance, support,
updates, enhancements, or modifications.

=cut