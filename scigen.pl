#!/usr/bin/perl

#
# simple context-free grammar expander
#
# $Id$
#

use IO::File;
use strict;
use Data::Dumper;
use Autoformat;

my $debug = 0;
my $pretty = 1;

use vars qw [ $RE ];

sub dup_name {
    my $name = shift;
    return $name . "!!!";
}

sub read_rules {
    my ($fh, $rules, $name) = @_;
    my $line;
    while ($line = <$fh>) {
	next if $line =~ /^#/ ;
	next if $line !~ /\S/ ;
	    
	my @words = split /\s+/, $line;
	my $name = shift @words;
	my $rule = "";

	# non-duplicate rule
	if( $name =~ /([^\+]*)\!$/ ) {
	    $name = $1;
	    push @{$rules->{dup_name("$name")}}, "";
	    next;
	}

	if ($#words == 0 && $words[0] eq '{') {
	    my $end = 0;
	    while ($line = <$fh>) {
		if ($line eq "}\n") {
		    $end = 1;
		    last;
		} else {
		    $rule .= $line;
		}
	    }
	    if (! $end) {
		die "$name: EOF found before close rule\n";
	    }
	} else {
	    $line =~ s/^\S+\s+//; 
	    chomp ($line);
	    $rule = $line;
	}

	# look for the weight
	my $weight = 1;
	if( $name =~ /([^\+]*)\+(\d+)$/ ) {
	    $name = $1;
	    $weight = $2;
	    if( $debug > 10 ) {
		warn "weighting rule by $weight: $name -> $rule\n";
	    }
	}

	do {
	    push @{$rules->{$name}}, $rule;
	} while( --$weight > 0 );
    }
}


sub generate {
    my ($rules, $start) = @_;

    # must sort; order matters, and we want to make sure that we get
    # the longest matches first
    my $in = join "|", sort { length ($b) <=> length ($a) } keys %$rules;

    $RE = qr/^(.*?)(${in})/s ;
    my $s = expand ($rules, $start);
    if( $pretty ) {
	$s = pretty_print($s);
    }
    print "$s\n";
}

sub pick_rand {
    my ($set) = @_;
    my $n = $#$set + 1;
    my $v =  @$set[int (rand () * $n)];
    return $v;
}

sub pop_first_rule {
    my ($rules, $preamble, $input, $rule) = @_;

    $$preamble = undef;
    $$rule = undef;

    my $ret = undef;
    
    if ($$input =~ s/$RE//s ) {
	$$preamble = $1;
	$$rule = $2;
	return 1;
    }
	
    return 0;
}

sub pretty_print {

    my ($s) = shift;

    my $news = "";
    my @lines = split( /\n/, $s );
    foreach my $line (@lines) {

	my $newline = "";

	$line =~ s/(\s+)([\.\,\?\;\:])/$2/g;
	$line =~ s/(\W+)(a) ([aeiou])/$1$2n $3/gi;

	if( $line =~ /\\section(\*?){(.*)}/ ) {
	    $newline = "\\section${1}{" . 
	      Autoformat::autoformat( $2, { case => 'highlight', 
					    squeeze => 0 } );
	    chomp $newline;
	    chomp $newline;
	    $newline .= "}\n";
	} elsif( $line =~ /\\subsection{(.*)}/ ) {
	    $newline = "\\subsection{" . 
	      Autoformat::autoformat( $1, { case => 'highlight', 
					    squeeze => 0 } );
	    chomp $newline;
	    chomp $newline;
	    $newline .= "}\n";
	} elsif( $line =~ /\\title{(.*)}/ ) {
	    $newline = "\\title{" . 
	      Autoformat::autoformat( $1, { case => 'highlight', 
					    squeeze => 0  } );
	    chomp $newline;
	    chomp $newline;
	    $newline =~ s/\\Em/\\em/g;
	    $newline .= "}\n";
	} elsif( $line =~ /(.*) = {(.*)}\,/ ) {
	    my $label = $1;
	    my $curr = $2;
	    # place brackets around any words containing capital letters
	    $curr =~ s/(\s+)([^\s]*[A-Z]+[^\s\:]*)(\:?\s+)/$1\{$2\}$3/g;
	    $curr =~ s/^([^\s]*[A-Z]+[^\s\:]*)(\:?\s+)/\{$1\}$2/g;
	    $curr =~ s/(\s+)([^\s]*[A-Z]+[^\s\:]*)$/$1\{$2\}/g;
	    $newline = "$label = {" . 
	      Autoformat::autoformat( $curr, { case => 'highlight', 
					       squeeze => 0  } );
	    chomp $newline;
	    chomp $newline;
	    $newline =~ s/\\Em/\\em/g;
	    $newline .= "},\n";
	} else {
	    $newline .= 
	      Autoformat::autoformat( $line, { case => 'sentence', 
					       squeeze => 0, 
					       break => break_latex(),
					       ignore => qr/^\\/ } );
	    chomp $newline;
	    chomp $newline;
	    $newline .= "\n";
	}

	$news .= $newline;

    }

    return $news;
}

sub break_latex($$$) {
    my ($text, $reqlen, $fldlen) = @_;
    return { $text, "" };
}

sub expand {
    my ($rules, $start) = @_;

    # check for special rules ending in + and # 
    # Rules ending in + generate a sequential integer
    # The same rule ending in # chooses a random # from among preiously
    # generated integers
    if( $start =~ /(.*)\+$/ ) {
	my $rule = $1;
	my $i = $rules->{$rule};
	if( !defined $i ) {
	    $i = 0;
	    $rules->{$rule} = 1;
	} else {
	    $rules->{$rule} = $i+1;
	}
	return $i;
    } elsif( $start =~ /(.*)\#$/ ) {
	my $rule = $1;
	my $i = $rules->{$rule};
	if( !defined $i ) {
	    $i = 0;
	} else {
	    $i = int rand $i;
	}
	return $i;
    }
    my $full_token;

    my $repeat = 0;
    do {

	my $input = pick_rand ($rules->{$start});
	if ($debug >= 5) {
	    warn "$start -> $input\n";
	}

	my ($pre, $rule);
	my @components;
	$repeat = 0;	

	while (pop_first_rule ($rules, \$pre, \$input, \$rule)) {
	    my $ex = expand ($rules, $rule);
	    push @components, $pre if length ($pre);
	    push @components, $ex if length ($ex);
	}
	push @components, $input if length ($input);
	$full_token = join "", @components ;
	my $ref = $rules->{dup_name("$start")};
	if( defined $ref ) {
	    my @dups = @{$ref};
	    # make sure we haven't generated this exact token yet
	    foreach my $d (@dups) {
		if( $d eq $full_token ) {
		    $repeat = 1;
		}
	    }
	    
	    if( !$repeat ) {
		push @{$rules->{dup_name("$start")}}, $full_token;
	    } elsif( ($#dups-1) == $#{@{$rules->{$start}}} ) {
		$full_token = "";
		$repeat = 0;
	    }
	    
	}

    } while( $repeat );

    return $full_token;
    
}


# main
my $dat = {} ;
my $fh;
my $filename;
my $start = "START";

use Getopt::Long;

# parse args
my $result = GetOptions ("filename=s" => \$filename,
			 "start=s"    => \$start,
			 "pretty=i"    => \$pretty,
			 "debug=i"    => \$debug );

if ( $filename ) {
    $fh = new IO::File ("<$filename");
    die "cannot open input file: $filename\n" unless $fh;
} else {
    $filename = "STDIN";
    $fh = \*STDIN;
}

foreach my $arg (@ARGV) {
    my ($n,$v) = split /=/, $arg;
    push @{$dat->{$n}}, $v;
}

# run
read_rules ($fh, $dat, $filename);
generate ($dat, $start);
