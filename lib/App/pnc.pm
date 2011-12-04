package App::pnc;

our $VERSION = '0.02';

use strict;
use warnings;

use Socket;
use Carp;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Errno qw(ENOTSOCK);

our $max_buffer_size = 64 * 1024;

sub netcat4 {
    my ($server, $port) = @_;
    if ($port =~ /\D/) {
        $port = getservbyname($port, 'tcp')
            or croak "unable to convert service name to port number: $!";
    }
    my $iaddr = inet_aton($server) or croak "unable to resolve host name: $!";
    my $paddr = sockaddr_in($port, $iaddr);
    socket (my $socket, AF_INET, SOCK_STREAM, 0) or croak "unable to create socket: $!";
    connect ($socket, $paddr) or croak "unable to connect to host: $!";

    _netcat($socket);
}

sub netcat6 {
    #my ($server, $port) = @_;
    #_netcat($server, AF_INET6, $port);
    croak "not implemented yet!";
}

sub _shutdown {
    my ($socket, $dir) = @_;
    unless (shutdown($socket, $dir)) {
        if ($! == ENOTSOCK) {
            return close ($socket);
        }
    }
    undef;
}

sub _netcat {
    my $socket = shift;

    for my $fh ($socket, *STDIN, *STDOUT) {
        my $flags = fcntl($fh, F_GETFL, 0);
        fcntl($fh, F_SETFL, fcntl($fh, F_GETFL, 0) | O_NONBLOCK);
        binmode $fh;
    }

    my @in = (*STDIN, $socket);
    my @out = ($socket, *STDOUT);
    my @buffer = ('', '');

    my @in_open = (1, 1);
    my @out_open = (1, 1);

    local $SIG{PIPE} = 'IGNORE';

    while (grep $_, @in_open, @out_open) {
        my $iv = '';
        my $ov = '';
        for my $ix (0, 1) {
            if ($in_open[$ix] and length $buffer[$ix] < $max_buffer_size) {
                vec($iv, fileno($in[$ix]), 1) = 1;
            }
            if ($out_open[$ix] and length $buffer[$ix] > 0) {
                vec($ov, fileno($out[$ix]), 1) = 1;
            }
        }
        if (select($iv, $ov, undef, 5) > 0) {
            for my $ix (0, 1) {
                if ($in_open[$ix] and vec($iv, fileno($in[$ix]), 1)) {
                    my $bytes = sysread($in[$ix], $buffer[$ix], 16 * 1024, length $buffer[$ix]);
                    unless ($bytes) {
                        $in_open[$ix] = 0;
                        _shutdown($in[$ix], 0);
                        unless (length $buffer[$ix]) {
                            $out_open[$ix] = 0;
                            _shutdown($out[$ix], 1);
                        }
                    }
                }
                if ($out_open[$ix] and vec($ov, fileno($out[$ix]), 1)) {
                    my $bytes = syswrite($out[$ix], $buffer[$ix], 16 * 1024);
                    if ($bytes) {
                        substr($buffer[$ix], 0, $bytes, '');
                        unless ($in_open[$ix] or length $buffer[$ix]) {
                            $out_open[$ix] = 0;
                            _shutdown($out[$ix], 1);
                        }
                    }
                    else {
                        $out_open[$ix] = 0;
                        _shutdown($out[$ix], 1);
                        $buffer[$ix] = '';
                        if ($in_open[$ix]) {
                            $in_open[$ix] = 0;
                            _shutdown($in[$ix], 0);
                        }
                    }
                }
            }
        }
    }
    for my $fd ($socket, *STDIN, *STDOUT) {
        close $fd;
    }
}

unless (defined caller) {
    if (@ARGV == 1 and $ARGV[0] eq '-V') {
        print "pnc $VERSION, a netcat alike program written in Perl\n\n";
    }
    elsif (@ARGV == 2) {
        netcat4(@ARGV);
    }
    else {
        @ARGV == 2 or die "Usage:\n    pnc host port\n\n";
    }
}


1;

__END__

=head1 NAME

App::pnc - Simple netcat clone implemented in Perl.

=head1 SYNOPSIS

  use App::pnc;
  App::pnc::netcat4($host, $port);

=head1 DESCRIPTION

This is a simple netcat alike program written in Perl.

It has no dependencies besides Perl 5.005 and uses a simple file so
that it can be easily copied into a remote system.

=head1 SEE ALSO

L<Net::OpenSSH::Gateway>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Salvador Fandino, E<lt>sfandino@yahoo.com<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.


=cut
