#!/usr/bin/perl
# Parse aggregated sudoers dump files
# 2017/09/24 - TRCM - first stab
# 2017/09/25 - TRCM - Initial server block import complete
#                   - parse sub-blocks into {global,regional,local}
#                   - implement proper option parsing (getopt)
#                   - option to list available blocks for specific server,
#                     and print a single wanted block for that server.
# 2017/09/26 - TRCM - Capture sudo data orphaned outside blocks
#                   - Stop processing remainder of file once all wanted servers are found
#                   - option to suppress comments
#                   - always remove blank lines
#                   - sub-block matching regex updated to #{3,5}
# 2017/09/27 - TRCM - Gather global rule set version numbers.
#                   - Fix bug where choosing orphaned block would print all lines.
#                   - option extended to allow multiple server names
# 2017/09/28 - TRCM - Progress spinner
#                   - Rearrange the hash structure for clarity.
#                   - Record and print the '## GBLVER:' if we find it.
#                   - Record any #include lines if we find them.
# 2017/09/29 - TRCM - Join lines continued with backslashes
#                   - Brashly ignore deep recursion warnings due to the above
# 2017/10/02 - TRCM - Work on performance, fix missing server bug
# 2017/10/02 - TRCM - Refactored comment regex, swap spinner for progress bar
#                   - ANSI code '\e[K' to overwrite bar on first print
# 2017/10/04 - TRCM - Include alias and spec parsing code, and option to view
# 2017/10/05 - TRCM - Complete ability to print just selected blocks.
#                   - Add expand_cmnd_alias subroutine for later use...
#                   - Regex defined in variables where possible
# 2017/10/05 - TRCM - Procrastinating, added colour and cosmetic changes
#                   - Small fixup of comment matching regex
#                   - Finish output-commands-only argument function
# 2017/10/09 - TRCM - Only use ANSI colour when interactive STDOUT
#                   - Remove ANSI code '\e[K' so we play nice when (! -t STDOUT)
#                   - Repeat RunAs user and PASSWD|EXEC modifiers for each command
# 2017/10/10 - TRCM - Split commands on comma, only when not bracketed.
#                   - Moved printing to subroutines where possible
# 2017/10/16 - TRCM - Fix bug - RunAs username can include '_'.
#
# TODO Sudo Analysis ----------------------------------------------------------
# TODO - Parse 'Defaults' and '#include' into separate always-print blocks?
# FIXME - Check sudoers syntax for where PASSWD|EXEC modifiers are allowed in string.
#       - Can modifiers exist in Cmnd_Alias?
#
# TODO Performance ------------------------------------------------------------
# TODO - Use Storage to save and load the parsed sudoers hash?
# TODO - For largest use case (1GB data file), we use approx 3GB RAM,
#        This is probably a bit too high, so discard/process data as we go.
#
use strict;
use warnings;
# TODO Move recursion disable statement into affected block.
no warnings 'recursion'; # Often recurse >100 times whilst join_backslashed()
use Data::Dumper;
use Getopt::Long;
our $VERSION = "0.961";
my $name = __FILE__; $name =~ s/.*\///;
#------------------------------------------------------------------------------
# Regex matching for sudoers block separators
my $re_server_start = qr/^#{4,6}\ START_OF_SUDOERS/;
my $re_server_name  = qr/^#{4,6}\ START_OF_SUDOERS_FOR_([\w\.\=]+)/;
my $re_server_end   = qr/^#{4,6}\ END_OF_SUDOERS/;
my $re_block_start  = qr/#{3,5}\ START\ #{3,5}$/;
my $re_block_end    = qr/#{3,5}\ END\ #{3,5}$/;
#------------------------------------------------------------------------------
my ($sudofile,@wantservers,%wantservers_lu,@wantblocks,$debug,$wantcommands,$ignore);
wtf() unless scalar @ARGV > 0 or (-t STDIN);
GetOptions ('h|help|v|?'     => sub{ info($VERSION);wtf(); },
            'f|file=s'       => \$sudofile,
            'd|debug'        => \$debug,
            'c|commands'     => \$wantcommands,
            'i|ignore'       => \$ignore,
            's|servername=s' => \@wantservers,
            'b|block:s'      => sub{if ($_[1]) {@wantblocks=$_[1]} else {@wantblocks=('listall')}},
            'v'              => sub{ info($VERSION);exit 0; },
) or wtf();
wtf() unless defined($sudofile);
die" ! Unable to read sudoers_file : $sudofile\n" unless (-r $sudofile);
# We want lists, not comma separated strings.
@wantservers = split(/,/,join(',',@wantservers));
@wantblocks = split(/,/,join(',',@wantblocks));
# Having a lookup table of our wanted servers is handy.
%wantservers_lu = map { $_ => 1; } @wantservers;
#------------------------------------------------------------------------------
my $server;
my %hash;
# TODO - benchmark if this is a worthwhile optimisation
keys %hash = 10000; # Pre-allocate 10000 buckets.
importdata($sudofile);
#------------------------------------------------------------------------------
if (@wantservers) {
    # Printing results for selected servernames
    foreach my $server (@wantservers) {
        process_server(\%hash,\$server,\@wantblocks);
    }
} else {
    # Printing results for all servernames
    foreach my $server (sort keys %hash) {
        process_server(\%hash,\$server,\@wantblocks);
    }
}
print STDERR ("[?] DEBUG: Size of hash : " . scalar keys %hash) . "\n" if ($debug);
print STDERR ("[?] DEBUG: Processed $. in total.\n") if ($debug);
#------------------------------------------------------------------------------
sub process_server {
    my $hash_ref = shift;
    my $server_ref = shift;
    my $wantblocks_ref = shift;
    if (exists($hash_ref->{$$server_ref})) {
        # We have data for a server we wanted, lets print it
        my $block_found;
        my %block_seen;
        print header("[+] Server:$$server_ref, GBLVER:$hash_ref->{$$server_ref}{'GBLVER'}, INCLUDES:$hash_ref->{$$server_ref}{'INCLUDE'}\n");
        if (@$wantblocks_ref and scalar @$wantblocks_ref == 1 and @$wantblocks_ref[0] eq 'listall') {
            print_list_all_server_blocks($hash_ref,$server_ref);
        } elsif (@$wantblocks_ref and scalar @$wantblocks_ref >=1) {
            # Show specific blocks found for each server
            foreach my $wantblock (@$wantblocks_ref) {
                foreach my $block (sort keys %{$hash_ref->{$$server_ref}{'SUDO'}}) {
                    if ($block =~ m/^$wantblock/ and not exists($block_seen{$block})) {
                        $block_found++;
                        $block_seen{$block}++;
                        print header("[-] Sudo block matching \"$wantblock\" : $block\n");
                        if ($wantcommands) {
                            print_specs_one_server_block($hash_ref,$server_ref,\$block);
                        } else {
                            print_contents_one_server_block($hash_ref,$server_ref,\$block);
                        }
                    }
                }
                print header("[!] No sudoers blocks matching \"$wantblock\"\n") unless ($block_found);
                undef $block_found;
            }
        } else {
            ## Show all blocks for each server
            print_contents_all_server_blocks($hash_ref,$server_ref,\$block_found);
        }
    } else {
        ### We can't find data for a server we wanted
        print header("[!] ERROR Servername : $$server_ref not found.\n");
    }
    printf("%s\n",'-'x78);
    return;
}
#------------------------------------------------------------------------------
sub print_specs_one_server_block {
    # Print each possible user command as we iterate over Specifications and
    # their expanded command aliases
    my $hash_ref = shift;
    my $server_ref = shift;
    my $block_ref = shift;
    foreach my $user (sort {lc $a cmp lc $b} keys %{$hash_ref->{$$server_ref}{'PARSED'}{$$block_ref}{'Spec'}}) {
        foreach my $host (sort keys %{$hash_ref->{$$server_ref}{'PARSED'}{$$block_ref}{'Spec'}{$user}}) {
            foreach my $cmd (sort {$a cmp $b} keys %{$hash_ref->{$$server_ref}{'PARSED'}{$$block_ref}{'Spec'}{$user}{$host}{'Cmnd_Alias'}}) {
                $cmd =~ s/\ \ /\ /g;
                my $modifiers='';
                my $runas='(ALL)'; # Unless specified, you get to be anyone, right?
                # Make sure we only split on a comma which isn't enclosed in brackets.
                foreach my $eachcmd (map {trim($_)} split(/(?![^(]+\)),/,$cmd)) {
                    # Strip all modifiers and save to $modifiers
                    $eachcmd =~ s/((?:NOPASSWD:|PASSWD:|NOEXEC:|EXEC:)+)/$modifiers=$1;''/ge;
                    # Strip RunAs user and save to $runas
                    $eachcmd =~ s/^(\([a-zA-Z0-9_,]+\))/$runas=$1;''/ge;
                    $eachcmd = trim($eachcmd);
                    # Is this command an alias?
                    if ($eachcmd =~ /^[A-Z0-9_]+$/) {
                        if (exists $hash_ref->{$$server_ref}{'PARSED'}{$$block_ref}{'Cmnd_Alias'}{$eachcmd}) {
                            foreach my $subeachcmd (@{$hash_ref->{$$server_ref}{'PARSED'}{$$block_ref}{'Cmnd_Alias'}{$eachcmd}}) {
                                print("$$server_ref,$$block_ref,$user,$host,$runas,$modifiers$subeachcmd\n");
                            }
                        } else {
                            print("$$server_ref,$$block_ref,$user,$host,$runas,$modifiers$eachcmd\n");
                        }
                    } else {
                        print("$$server_ref,$$block_ref,$user,$host,$runas,$modifiers$eachcmd\n");
                    }
                }
            }
        }
    }
}
#------------------------------------------------------------------------------
sub print_list_all_server_blocks {
    # Just list all the available blocks we found for each server
    my $hash_ref = shift;
    my $servername_ref = shift;
    my $blockfound;
    print header("[-] List of available blocks...\n");
    foreach my $block (sort keys %{$hash_ref->{$$servername_ref}->{'SUDO'}}) {
        $blockfound++;
        print("\t$block\n");
    }
    print header("[!] No sudoers blocks found\n") unless ($blockfound);
    return;
}
#------------------------------------------------------------------------------
sub print_contents_one_server_block {
    ## Show all blocks for each server
    my $hash_ref = shift;
    my $server_ref = shift;
    my $block_ref = shift;
    foreach (@{$hash_ref->{$$server_ref}{'SUDO'}{$$block_ref}}) {
        print("$_\n");
    }
}
#------------------------------------------------------------------------------
sub print_contents_all_server_blocks {
    ## Show all blocks for each server
    my $hash_ref = shift;
    my $servername_ref = shift;
    my $blockfound_ref = shift;
    foreach my $block (keys %{$hash_ref->{$$servername_ref}->{'SUDO'}}) {
        $$blockfound_ref++;
        print header("[-] Sudo block : $block ...\n");
        foreach (@{$hash_ref->{$$servername_ref}->{'SUDO'}->{$block}}) {
            print("$_\n");
        }
    }
    print header("[!] No sudoers blocks found\n") unless ($$blockfound_ref);
    return;
}
#------------------------------------------------------------------------------
sub importdata {
    # Read the entire file, and split into chunks per server.
    my $sudofile = shift;
    open (my $FH,'<',$sudofile) || die;
    my $data_lc = count_lines($FH); seek($FH,0,0); $.=0;
    print "[?] DEBUG : File position \$\. is at : $.\n" if ($debug);
    my $inside_block;
    while (my $line = <$FH>) {
        if ($.%50000==0) {
            print STDERR progress_bar($.,$data_lc,40,'=');
        }
        chomp $line;
        #$line =~ s/\015?\012?$//; # Portable chomp
        # Always remove blank lines.
        next if $line =~ m/^\s*$/;
        if (defined($ignore)) {
            # Skip comments unless 'include' lines, or looking like block tags
            next if $line =~ m/^\s*#(?!incl|#{1,5}\ )/;
            next if $line =~ m/^##\ (?!GBLVER:[0-9\.]+$)/;
            # Skip ill-formed block tags like '### Start HPSA ###'
            next if $line =~ m/^(#{2,5})(\s\w+){2,6}?\s\1$/;
        }
        undef $inside_block if $line =~ m/$re_server_end|$re_server_start/;
　
        # Record the Global sections version identifier
        if ($line =~ m/^## GBLVER:([0-9\.]+)/) {
            $hash{$server}{'GBLVER'}=$1;
            next;
        }
　
        # Flag up #include lines as their data may not be in the data collected
        $hash{$server}{'INCLUDE'}++ if ($line =~ m/^#include/ and exists($hash{$server}));
　
        if ($inside_block) {
            if (@wantblocks and scalar @wantblocks == 1 and $wantblocks[0] eq 'listall') {
                # Speed optimisation here, if we want just list of blocks,
                # avoid slow recursive join_backslashed()
                # 12mins/GB down to 4mins/GB
                push (@{$hash{$server}{'RAW'}}, $line);
                next;
            } else {
                # Join lines which have been continued with a trailing backslash
                # We do this only if inside_block to save time.
                if ($line =~ m/\\\s*$/) {
                    ($line, $FH) = join_backslashed(\$line, \$FH);
                }
                push (@{$hash{$server}{'RAW'}}, $line);
                next;
            }
        }
        if ($line =~ m/$re_server_start/) {
            $inside_block++;
            ($server) = $line =~ m/$re_server_name/;
            # Initialise the bad '#include' counter to zero.
            $hash{$server}{'INCLUDE'}=0;
            # Initialise the Global Version number
            $hash{$server}{'GBLVER'}="unknown";
            undef $inside_block if ((@wantservers) and (not exists $wantservers_lu{$server}));
            next;
        }
        if ($line =~ m/$re_server_end/) {
            if ((@wantservers) and exists $wantservers_lu{$server}) {
                # We want specific servers, and this is one of them
                parse_raw($server);
                # It's done, remove it from our lookup list
                delete $wantservers_lu{$server};
                print STDERR ("[?] DEBUG: ($server) done, servers left=".scalar(keys %wantservers_lu)."\n") if ($debug);
                if (scalar(keys %wantservers_lu) == 0) {
                    # Stop as we parsed the last of our wanted servers
                    print STDERR ("[?] DEBUG: fast importdata exit at line : $.\n") if ($debug);
                    last;
                } else {
                    next;
                }
            } elsif (not @wantservers) {
                # We wanted every server, just process it.
                parse_raw($server);
            } else {
                # We wanted some servers, this isn't it
                next;
            }
        }
    }
    close($FH);
    return;
}
#------------------------------------------------------------------------------
sub join_backslashed {
    my ($lineref,$fhref) = @_;
    my $line=$$lineref;
    my $fh=$$fhref;
    if ($line =~ s/\\\s*$//) {
        $line .= <$fh>;
        $line =~ s/\s+/ /g;
        ($line, $fh) = join_backslashed(\$line, \$fh);
    }
    return ($line, $fh);
}
#------------------------------------------------------------------------------
sub parse_raw {
    my $server = shift;
    my $block_name;
    my $block_inside;
    foreach (@{$hash{$server}{'RAW'}}) {
        undef $block_inside if m/$re_block_start|$re_block_end/;
        if ($block_inside) {
            # Step 1, just add the line to the named block array
                # We're inside a block, add the line to the named block array
                push (@{$hash{$server}{'SUDO'}{$block_name}}, $_);
            # Step 2, parse the alias or spec lines, adding to hash
                if (defined($wantcommands)) {
                    # Only if we supplied the '-c' argument...
                    if (s/^\s*User_Alias\s+//) {
                        $hash{$server}{'PARSED'}{$block_name}->{'User_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{$block_name}->{'User_Alias'});
                    } elsif (s/^\s*Cmnd_Alias\s+//) {
                        $hash{$server}{'PARSED'}{$block_name}->{'Cmnd_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{$block_name}->{'Cmnd_Alias'});
                    } elsif (s/^\s*Host_Alias\s+//) {
                    #    $hash{$server}{'PARSED'}->{'Host_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}->{'Host_Alias'});
                    } elsif (s/^\s*Runas_Alias\s+//) {
                    #    $hash{$server}{'PARSED'}->{'Runas_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}->{'Runas_Alias'});
                    } elsif (m/^\s*\S+\s+\S+\s*=\s*\S+/) {
                        if (m/Default/) {
                            print "[?] DEBUG: Erroneously matched a defaults line : $_\n" if ($debug);
                            next;
                        }
                        $hash{$server}{'PARSED'}{$block_name}->{'Spec'} = parse_spec($_,$hash{$server}{'PARSED'}{$block_name}->{'Spec'});
                    } else {
                        print "[?] DEBUG: unknown line: ${_}\n" if ($debug);
                    }
                }
            # Step 3, continue to next line
                next;
        } elsif (not m/$re_block_start|$re_block_end/) {
            # We're outside both block and block-tags, add line to ORPHANED block array
            push (@{$hash{$server}{'SUDO'}{'ORPHANED'}}, $_);
            if (defined($wantcommands)) {
                # Only if we supplied the '-c' argument...
                if (s/^\s*User_Alias\s+//) {
                    $hash{$server}{'PARSED'}{'ORPHANED'}->{'User_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{'ORPHANED'}->{'User_Alias'});
                } elsif (s/^\s*Cmnd_Alias\s+//) {
                    $hash{$server}{'PARSED'}{'ORPHANED'}->{'Cmnd_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{'ORPHANED'}->{'Cmnd_Alias'});
                } elsif (s/^\s*Host_Alias\s+//) {
                #    $hash{$server}{'PARSED'}{'ORPHANED'}->{'Host_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{'ORPHANED'}->{'Host_Alias'});
                } elsif (s/^\s*Runas_Alias\s+//) {
                #    $hash{$server}{'PARSED'}{'ORPHANED'}->{'Runas_Alias'} = parse_alias($_,$hash{$server}{'PARSED'}{'ORPHANED'}->{'Runas_Alias'});
                } elsif (m/^\s*\S+\s+\S+\s*=\s*\S+/) {
                    if (m/Default/) {
                        print "[?] DEBUG: Erroneously matched a defaults line : $_\n" if ($debug);
                        next;
                    }
                    $hash{$server}{'PARSED'}{'ORPHANED'}->{'Spec'} = parse_spec($_,$hash{$server}{'PARSED'}{'ORPHANED'}->{'Spec'});
                }
            }
            next;
        }
        if (m/$re_block_start/) {
            # We're starting a new block, remember its name
            $block_inside++;
            # '#{3,5} BLOCK_NAME #{3,5} (START|END) #{3,5}'
            # FIXME - using split is crap, what about a lookaround regex capture?
            #       - something like...
            #       - m/^(?=#{3,5}\ (GLOBAL|REGIONAL|LOCAL)_)([\w]+)\ /
            $block_name = trim((split(/\ /,$_,3))[1]);
            next;
        }
    }
    # Once we've parsed the whole server block, discard the RAW data
    delete $hash{$server}{'RAW'};
    return;
}
#------------------------------------------------------------------------------
sub parse_alias {
    my ($line,$alias) = @_;
    $line = trim($line);
    my ($name,$raw_value) = split(/\s*=\s*/,$line,2);
    my @values = split(/\s*,\s*/,$raw_value);
    $alias->{$name} = \@values;
    return $alias;
}
#------------------------------------------------------------------------------
sub parse_spec {
    my ($line,$spec) = @_;
    $line = trim($line);
    $line =~ m/\s*?(\S+)\s+\S+\s*?=\s*?.+/;
    my $userlist = $1;
    # Some stupid lines have user1,user2,user3,userN. Split on ',' and iterate over users
    my @users = split(/,/,$userlist);
    foreach my $user (@users) {
        foreach my $bit ($line =~ m/\S+\s*=\s*(?:\(\S+\))?\s*?(?:NOPASSWD:\s*?|PASSWD:\s*?)?(?:NOEXEC:\s*|EXEC:\s*?)?\s*?.*/g) {
            $bit =~ m/\s*(\S+)\s*=\s*(.+)\s*(?::|$)/;
            my $host = $1;
            my $cmnd = $2;
            $cmnd =~ s/\s+:\s+/:/;
            $spec->{$user}->{$host}->{'Cmnd_Alias'}->{$cmnd} = '1';
        }
    }
    return $spec;
}
#------------------------------------------------------------------------------
sub expand_cmnd_alias {
    my ($command,$hash) = @_;
    my $temp;
    my $cmnd_alias = $hash->{'Cmnd_Alias'}{$command};
    foreach my $command (@{$cmnd_alias}) {
        if ($command =~ /^[A-Z0-9_]+$/) {
            $temp->{$command} = expand_cmnd_alias($command,$hash);
        } else {
            $temp->{$command} = undef;
        }
    }
    return $temp;
}
#------------------------------------------------------------------------------
sub trim {
    my $s_string = shift;
    $s_string =~ s/^\s+|\s+$//g;
    return $s_string;
}
#------------------------------------------------------------------------------
sub header {
    # Only print with ANSI colour codes if we have an interactive term
    my $text = shift;
    my $yellow = "\e[33m";
    my $green = '';
    my $plain = "\e[m";
    if (-t STDOUT) {
        return $yellow,$text,$plain;
    }
    return $text;
}
#------------------------------------------------------------------------------
sub progress_bar {
    my ( $curr, $total, $width, $char ) = @_;
    $width ||= 25; $char ||= '=';
    my $num_width = length $total;
    return sprintf "[%-${width}s] read %${num_width}s lines of %s total (%.1f%%)\r",
        $char x (($width-1)*$curr/$total). '>',
        $curr, $total, 100*$curr/+$total;
}
#------------------------------------------------------------------------------
sub count_lines {
    my ($fh) = shift;
    while(<$fh>) {};
    my $count = $.;
    return $count;
}
#------------------------------------------------------------------------------
sub info {
    my $s_version = shift;
    printf("\e[%dm%s\e[m - %s (PERL v%vd)\n",33,$name,$s_version,$^V);
    return;
}
#------------------------------------------------------------------------------
sub wtf {
    printf("Usage: \e[%dm%-12s\e[m [-i] [-c] -f sudoers_file [-s servername(s)] [-b block(s)]\n",33,$name);
    print("       '-s  <server>,<server>,...' Multiple servers can be separated by commas\n");
    print("       '-b' Without a block name will list available blocks found\n");
    print("       '-b  <block>,<block>,...' Multiple blocks can be separated by commas\n");
    print("       '-c' will only print command specifications\n");
    print("       '-i' will ignore/suppress commented lines\n");
    exit;
}
#------------------------------------------------------------------------------
__END__
