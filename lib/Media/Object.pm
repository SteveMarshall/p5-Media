use Modern::Perl;
use MooseX::Declare;

class Media::Object {
    with 'Media::Queue';
    use Media::Handler;
    
    use File::Path      qw( mkpath );
    
    use constant AVAILABLE_HANDLERS => qw( ConfigFile TV Movie MusicVideo );
    use constant AVAILABLE_MEDIA    => qw( DVD VideoFile );
    
    has full_configuration => (
        isa      => 'HashRef',
        is       => 'ro',
        required => 1,
    );
    has config_file => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    has encode_directory => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    has cache_directory => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    has queue_directory => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    has encoder_pid_file => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    has encoder_pid_file => (
        isa      => 'Str',
        is       => 'ro',
        required => 1,
    );
    
    method BUILD {
        # ensure any directories exist
        my @required = qw( encode_directory queue_directory cache_directory );
        
        foreach my $require ( @required ) {
            my $dir = $self->$require;
            mkpath $dir;
        }
    }
    
    
    method encode_media ( $payload ) {
        my $type    = $payload->{'type'};
        my $medium  = $payload->{'medium'};
        my $details = $payload->{'details'};
        my $input   = $payload->{'input'};
        
        my $config = $input->{'media_conf'} // $self->config_file;
        my $handler;
        
        if ( $config ne $self->config_file ) {
            my $media = Media->new( $config );
            $handler = $media->get_handler( $type, $medium, $details, $input );
        }
        else {
            $handler = $self->get_handler( $type, $medium, $details, $input );
        }
        
        $handler->encode_content();
        $handler->add_metadata_to_content();
        $handler->install_content();
        $handler->post_install();
        $handler->add_to_itunes();
        $handler->clean_up_conversion();
    }
    method queue_media ( $input, $priority?, $hints?, $extra_args? ) {
        my $handler = $self->get_handler_for( $input, $hints );
        
        if ( defined $handler ) {
            $self->queue_conversion( $handler, $priority, $extra_args );
        }
        else {
            say STDERR "Unknown input: $input";
        }
    }
    
    method get_handler ( $type, $medium, $details, $input='' ) {
        return Media::Handler->new(
                type        => $type,
                medium      => $medium,
                details     => $details,
                input       => $input,
                config      => $self->full_configuration,
            );
    }
    method get_empty_handler ( $type?, $medium? ) {
        $type   = 'Empty' unless defined $type;
        $medium = 'Empty' unless defined $medium;
        
        return Media::Handler->new(
                type    => $type,
                medium  => $medium,
                details => {},
                input   => {},
                config  => $self->full_configuration,
            );
    }
    method get_handler_for ( $target, $hints? ) {
        my( $type, $details ) = $self->determine_type( $target, $hints );
        my( $medium, $input ) = $self->determine_medium( $target );
        
        # use Data::Dumper::Concise;
        # print Dumper \$type;
        # print Dumper \$details;
        # print Dumper \$medium;
        # print Dumper \$input;
        
        return $self->get_handler( $type, $medium, $details, $input )
            if defined $type && defined $medium;
        
        return;
    }
    method determine_type ( $string, $hints? ) {
        my $confidence = 0;
        my $type;
        my $details;
        
        foreach my $try ( AVAILABLE_HANDLERS ) {
            my $handler = $self->get_empty_handler( $try );
            
            my( $score, %d )
                = $handler->parse_title_string( $string, $hints );
            
            if ( defined $score ) {
                # score of -1 means "I know what I am, but there's a problem"
                return if $score == -1;
                
                if ( $score > $confidence ) {
                    $confidence = $score;
                    $type       = $handler->type;
                    $details    = \%d;
                }
            }
        }
        
        return( $type, $details );
    }
    method determine_medium ( $media ) {
        foreach my $try ( AVAILABLE_MEDIA ) {
            my $handler = $self->get_empty_handler( undef, $try );
            my $input   = $handler->can_use_medium( $media );
            
            return( $try, $input )
                if defined $input;
        }
    }
}
