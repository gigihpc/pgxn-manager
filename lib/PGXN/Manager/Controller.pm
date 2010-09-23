package PGXN::Manager::Controller;

use 5.12.0;
use utf8;
use PGXN::Manager;
use aliased 'PGXN::Manager::Request';
use PGXN::Manager::Templates;
use aliased 'PGXN::Manager::Distribution';
use HTML::Entities;
use Encode;
use namespace::autoclean;

Template::Declare->init( dispatch_to => ['PGXN::Manager::Templates'] );

sub render {
    my $self = shift;
    my $res = $_[1]->new_response(200);
    $res->content_type('text/html; charset=UTF-8');
    $res->body(encode_utf8 +Template::Declare->show(@_));
    return $res->finalize;
}

sub redirect {
    my ($self, $uri, $req) = @_;
    my $res = $req->new_response;
    $res->redirect($uri);
    return $res->finalize;
}

sub home {
    my $self = shift;
    my $req = Request->new(shift);
    return $self->render('/home', $req);
}

sub request {
    my $self = shift;
    return $self->render('/request', Request->new(shift), {
        description => 'Request a PGXN Account and start distributing your PostgreSQL extensions!',
        keywords => 'pgxn,postgresql,distribution,register,account,user,nickname',
    });
}

sub register {
    my $self   = shift;
    my $req    = Request->new(shift);
    my $params = $req->body_parameters;
    PGXN::Manager->conn->run(sub {
        $_->do(
            q{SELECT insert_user(
                nickname  := ?,
                password  := rand_str_of_len(5),
                full_name := ?,
                email     := ?,
                uri       := ?
            );},
            undef,
            @{ $params }{qw(
                nickname
                name
                email
            )}, $params->{uri} || undef,
        );

        # Success!
        $req->session->{name} = $req->param('name') || $req->param('nickname');
        $self->redirect('/thanks', $req);

    }, sub {
        # Failure!
        my $err = shift;
        my $msg;
        given ($err->state) {
            when ([qw(P0001 XX00)]) {
                (my $str = $err->errstr) =~ s/^[[:upper:]]+:\s+//;
                my @params;
                my $i = 0;
                $str =~ s{“([^”]+)”}{
                    push @params => $1;
                    '“[_' . ++$i . ']”';
                }gesm;
                $msg = [$str, @params];
            } when ('23505') {
                if ($err->errstr =~ /\busers_pkey\b/) {
                    $msg = [
                        'The Nickname “[_1]” is already taken. Sorry about that.',
                        delete $params->{nickname}
                    ];
                } else {
                    $msg = [
                        'Looks like you might already have an account. Need to <a href="/reset?email=[_1]">reset your password</a>?',
                        encode_entities delete $params->{email}
                    ];
                }
            }
            default {
                die $err;
            }
        }

        $self->render('/register', $req, {
            %{ $params },
            error => $msg,
        });
    });
}

sub thanks {
    my $self = shift;
    my $req  = Request->new(shift);
    return $self->render('/thanks', $req, { name => delete $req->session->{name}});
}

sub upload {
    my $self = shift;
    my $req  = Request->new(shift);
    my $upload = $req->uploads->{distribution};
    my $dist = Distribution->new(
        archive  => $upload->path,
        basename => $upload->basename,
        owner    => $req->remote_user,
    );
    $dist->process or $self->render_error($dist->error);
    $self->render('/done');
}

1;

=head1 Name

PGXN::Manager::Controller - The PGXN::Manager request controller

=head1 Synopsis

  # in PGXN::Manager::Router:
  use aliased 'PGXN::Manager::Controller';
  get '/' => sub { Root->home(shift) };

=head1 Description

This class defines controller actions for PGXN::Requests. Right now
it doesn't do much, but it's a start.

=head1 Interface

=head2 Actions

=head3 C<home>

  PGXN::Manager::Controller->home($env);

Displays the HTML for the home page.

=head3 C<auth>

  PGXN::Manager::Controller->auth($env);

Displays the HTML for the authorized user home page.

=head3 C<upload>

  PGXN::Manager::Controller->upload($env);

Handles uploads to PGXN.

=head3 C<request>

Handles requests for a form to to request a user account.

=head3 C<register>

Handles requests to register a user account.

=head3 C<thanks>

Thanks the user for registering for an account.

=head2 Methods

=head3 C<render>

  $root->render('/home', $req, @template_args);

Renders the response to the request using L<PGXN::Manager::Templates>.

=head3 C<redirect>

  $root->render('/home', $req);

Redirect the request to a new page.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2010 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
