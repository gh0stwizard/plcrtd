package Local::Templates; {
  use Object::InsideOut;
  use Template;
  use File::Temp;


  my @template
    :Field
    :Type( scalar )
    :Acc( 'Name' => 'template', 'Permission' => 'restricted' );

  my @stash
    :Field
    :Type( File::Temp )
    :Set( 'Name' => 'stash', 'Private' => 1, 'Return' => 'New' );

  my @error
    :Field
    :Get( error )
    :Set( 'Name' => 'set_error', 'Permission' => 'private' );


  sub generate {
    my ( $self ) = @_;


    my $tmp = $self->stash( File::Temp->new() );
    my $success = 0;
    my $config = {
      ENCODING => 'utf8',
      OUTPUT => $tmp,
    };

    if ( my $tt = Template->new( $config ) ) {
      my %data = $self->template_args();

      if ( $tt->process( \$self->template(), \%data ) ) {
        $success = 1;
      } else {
        $self->set_error( $tt->error() );
      }
    } else {
      $self->set_error( Template->error() );
    }

    close( $tmp );
    $success ? return $tmp->filename() : return;
  }

}

1;
