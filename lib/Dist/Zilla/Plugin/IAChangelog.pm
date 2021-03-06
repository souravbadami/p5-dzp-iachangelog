package Dist::Zilla::Plugin::IAChangelog;
# ABSTRACT: Add instant answer change log file to distro 

use Moose;
use namespace::autoclean;
with 'Dist::Zilla::Role::FileGatherer';

use Dist::Zilla::File::InMemory;
use DDG::Meta::Data;
use JSON::XS 'decode_json';
use IO::All;
use YAML::XS 'Dump';

use strict;

no warnings 'uninitialized';

has file_name => (
    is => 'ro',
    default => 'ia_changelog.yml'
);

has rename_threshold => (
    is => 'ro',
    default => 50
);

sub gather_files {
    my $s = shift;

    $s->log(["Creating instant answer change log (%s)", $s->file_name]);

    my $m = DDG::Meta::Data->by_id;

    my %share_paths;
    # The list of acceptable share paths is derived from the module names
    while(my ($k, $v) = each %$m){
        my $sp = $v->{perl_module};
        $sp =~ s/^DDG:://;
        $sp =~ s|::|/|g;
        $sp =~ s/([a-z])([A-Z])/$1_$2/g;
        $sp = lc $sp;
        $sp = "share/$sp";
        $share_paths{$sp} = $v->{id};
    }

    my $latest_tag  = (reverse(split /\s+/, `git tag -l [0-9]*`))[0];

    my $rt = $s->rename_threshold;
    open my $gd, "git diff $latest_tag.. --merges --name-status --diff-filter=AMDR --ignore-all-space --find-renames=$rt lib/ share/ |"
        or $s->log_fatal(["Failed to execute `git diff`: $!"]);

    my %decode_status = qw(
        A added
        D deleted
        M modified
        R modified
    );

    my $ia_types = qr/(?:goodie|spice|fathead|longtail)/i;
    my %changes;
    while(my $x = <$gd>){
        my ($status, @files) = split /\s+/, $x;

        # renames have format: R% file1 file2
        my $file = $status =~ s/^R\K\d+$// ? $files[1] : $files[0];

        my $id;
        if($file =~ m{lib/(DDG/$ia_types/.+)\.pm$}){
            my $m = $1;
            $m =~ s|/|::|g;
            if($m =~ /CheatSheets$/){
                $id = 'cheat_sheets';
            }
            else{
                while($m =~ /::/){
                    if(my $ia = DDG::Meta::Data->get_ia(module => $m)){
                        unless(@$ia == 1){
                            $s->log_fatal(["Multiple IDs in metadata for module $m: " . join(', ', map { $_->{id} } @$ia)]); 
                        }
                        $id = $ia->[0]{id};
                        last;
                    }
                    # Check if this is a child mod of an IA higher up
                    # If it is, status is "modified" with respect to the instant answer
                    $m =~ s/::[^:]+$//;
                    $status = 'M';
                }
            }
        }
        elsif($file =~ m{share/goodie/cheat_sheets/json/(.+)\.json$}){
            if($status eq 'D'){
                $id = $1;
                $id =~ s/-/_/g;
                $id .= '_cheat_sheet';
            }
            else{
                my $j = decode_json(io($file)->slurp);
                $id = $j->{id};
            }
        }
        elsif($file =~ m{(share/$ia_types/.+)/.+$}){
            my $sd = $1;
            # We check for exact matches, removing trailing directories in case assets
            # in subdirectories have been modified. Note that groups of IAs like,
            #
            #    spice/transit/njt
            #    spice/transit/path
            #    spice/transit/septa
            #
            # should never match a path of spice/transit since it won't exists as a module.
            do {
                if(exists $share_paths{$sd}){
                    $id = $share_paths{$sd};

                    # status for shared assets atm is always "modified" with respect to the IA
                    # since even the deletion or addition of an asset doesn't imply the same for
                    # the owning IA
                    $status = 'M';
                }
            } while $sd =~ s|/[^/]+$||;
        }
        else{
            $s->log_debug("Uknown file type $file...skipping");
            next;
        }

        if($id){
            # Overwrite modified with anything but not other statuses
            next unless (not exists $changes{$id}) || ($changes{$id} eq 'modified');
            $changes{$id} = $decode_status{$status};
        }
        else{
            my $msg = ["Failed to find to which instant answer file $file belongs!"];
            $status eq 'D' ? $s->log_debug($msg) : $s->log_fatal($msg);
        }
    }

    my $f = Dist::Zilla::File::InMemory->new({
        name => $s->file_name,
        content => Dump(\%changes)
    });

    $s->add_file($f);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=encoding utf8

=head1 NAME

Dist::Zilla::Plugin::IAChangelog - Add instant answer change log file to releases

=head1 SYNOPSIS

During release, attempts to determine which instant answers have been added,
modified, or deleted.  Outputs their metadata IDs and status to a YAML file.

This file is used by duckpan.org to update the statuses of instant answer pages
on the L<DuckDuckHack Community Platform|https://duck.co>.

To activate the plugin, add the following to F<dist.ini>:

    [IAChangelog]

=head1 ATTRIBUTES

=head2 file_name

Name of the file to be added to the release.  Since this is a YAML file
it makes sense to use a .yml extension, though it's not required.
Defaults to 'ia_changelog.yml'.

=head1 CONTRIBUTING

To browse the repository, submit issues, or bug fixes, please visit
the github repository:

=over 4

L<https://github.com/duckduckgo/p5-dzp-iachangelog>

=back

=head1 AUTHOR

Zach Thompson <zach@duckduckgo.com>

=cut
