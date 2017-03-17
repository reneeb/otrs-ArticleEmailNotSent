# --
# Copyright (C) 2017 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::ArticleEmailNotSent;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

=head1 NAME

Kernel::System::Ticket::ArticleEmailNotSent - Create an article in the ticket when an email could not be sent

=cut

sub Kernel::System::Ticket::ArticleSend {
    my ( $Self, %Param ) = @_;

    my $ToOrig      = $Param{To}          || '';
    my $Loop        = $Param{Loop}        || 0;
    my $HistoryType = $Param{HistoryType} || 'SendAnswer';

    # check needed stuff
    for (qw(TicketID UserID From Body Charset MimeType)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    if ( !$Param{ArticleType} && !$Param{ArticleTypeID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ArticleType or ArticleTypeID!',
        );
        return;
    }
    if ( !$Param{SenderType} && !$Param{SenderTypeID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need SenderType or SenderTypeID!',
        );
        return;
    }

    # map ReplyTo into Reply-To if present
    if ( $Param{ReplyTo} ) {
        $Param{'Reply-To'} = $Param{ReplyTo};
    }

    # clean up
    $Param{Body} =~ s/(\r\n|\n\r)/\n/g;
    $Param{Body} =~ s/\r/\n/g;

    # initialize parameter for attachments, so that the content pushed into that ref from
    # EmbeddedImagesExtract will stay available
    if ( !$Param{Attachment} ) {
        $Param{Attachment} = [];
    }

    # check for base64 images in body and process them
    $Kernel::OM->Get('Kernel::System::HTMLUtils')->EmbeddedImagesExtract(
        DocumentRef    => \$Param{Body},
        AttachmentsRef => $Param{Attachment},
    );

    # create article
    my $Time      = $Kernel::OM->Get('Kernel::System::Time')->SystemTime();
    my $Random    = rand 999999;
    my $FQDN      = $Kernel::OM->Get('Kernel::Config')->Get('FQDN');
    my $MessageID = "<$Time.$Random.$Param{TicketID}.$Param{UserID}\@$FQDN>";
    my $ArticleID = $Self->ArticleCreate(
        %Param,
        MessageID => $MessageID,
    );
    return if !$ArticleID;

    # send mail
    my ( $HeadRef, $BodyRef ) = $Kernel::OM->Get('Kernel::System::Email')->Send(
        'Message-ID' => $MessageID,
        %Param,
    );

    # return if no mail was able to send
    if ( !$HeadRef || !$BodyRef ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Message  => "Impossible to send message to: $Param{'To'} .",
            Priority => 'error',
        );

# ---
# PS
# ---
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $Subject      = $ConfigObject->Get('ArticleEmailNotSent::Subject') || 'Email could not be sent';
        my $Body         = $ConfigObject->Get('ArticleEmailNotSent::Body')
            || 'Email could not be sent - please ask your administrator';

        $Self->ArticleCreate(
            TicketID       => $Param{TicketID},
            ArticleType    => 'note-internal',
            SenderType     => 'system',
            Subject        => $Subject,
            Body           => $Body,
            ContentType    => 'text/plain; charset=utf-8',
            HistoryType    => 'AddNote',
            HistoryComment => 'Could not send email!',
            UserID         => $Param{UserID},
            NoAgentNotify  => 0,
        );
# ---
        return;
    }

    # write article to fs
    my $Plain = $Self->ArticleWritePlain(
        ArticleID => $ArticleID,
        Email     => ${$HeadRef} . "\n" . ${$BodyRef},
        UserID    => $Param{UserID}
    );
    return if !$Plain;

    # log
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'info',
        Message  => "Sent email to '$ToOrig' from '$Param{From}'. "
            . "HistoryType => $HistoryType, Subject => $Param{Subject};",
    );

    # event
    $Self->EventHandler(
        Event => 'ArticleSend',
        Data  => {
            TicketID  => $Param{TicketID},
            ArticleID => $ArticleID,
        },
        UserID => $Param{UserID},
    );

    return $ArticleID;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
