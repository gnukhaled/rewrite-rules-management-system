#!/usr/bin/perl 
#############################################################################
# Description: An engine to automatically manipulate Apache rewrite rules.
# Parameters : See the Usage() subroutine
# Returns    : 0 on Success, 1 on Error.
# Author     : Khaled Ahmed: khaled.gnu@gmail.com
# License    : GPL <http://www.gnu.org/licenses/gpl.html>
#############################################################################

use strict;
use Getopt::Long;
use Cwd 'abs_path';
use File::Basename;
use Sys::Hostname;
use Spreadsheet::XLSX;


our $VERSION 	     = 2.2;
our $absolute_path   = dirname(abs_path($0))."/";
our $rrms_confdir    = $absolute_path."conf/";
our $rrms_logsdir    = $absolute_path."logs/";
our $svndir;
our $serverList;
our $envname;
our $defaultenv;
our $ruleExisting    = 0;
our $isMicrosite     = 0;
our $isLocale        = 0;
our $envProvided     = 0;
our $concatDomains   = "";
our $SUDO            = "sudo";
our $svnuser         = "*FAKEUSER*";
our $svnpass         = "*FAKEPASS*";
our $localemail      = "*FAKEEMAIL*";
#our $localemail      = getlogin()."\@".hostname;
our %mail_addresses  = qw(Khaled khaled.gnu@gmail.com);
our %logtype         = qw(insert 0 update 1 delete 2 security 3 validation 4);
our @EmailMessage;
our @ValidationEmailMessage;
our $isDelete;
our $isBulk;
our $isRestore;
our $isRecover;
our $delSwitch;
our $username;
our $password;
our $srcURI;
our $dstURI;
our $origin_dstURI;
our $ruleType;
our @domains;
our $orig_domain;
our $UserName;
our @ExportedRules;
our @ListOfRules;
our @blkAll;
our $validation_status;
our @waitq;
our $lockfile = $absolute_path.".process.lck";
our $waitfile = $absolute_path.".waitq.lst";
our $env;
our $prod_env;
our $servlist;
our $svndirectory;
our $envsfile = $rrms_confdir."environments.conf";
our $productiondirective;
our $opt_help;
our $opt_delete;
our $opt_version;
our $opt_email;
our $opt_reload;
our $opt_deploy;
our $opt_silent;
our $opt_bulk;
our $opt_inline;
our $opt_recover;
our $opt_restore;
our $opt_env;
our $opt_validate;
our $opt_excel;


GetOptions(
'help!'     => \$opt_help,
'h!'	    => \$opt_help,
'delete!'   => \$opt_delete,
'd!'        => \$opt_delete,
'version!'  => \$opt_version,
'v!'        => \$opt_version,
'notify!'   => \$opt_email,
'silent!'   => \$opt_silent,
'file=s'    => \$opt_bulk,
'inline!'   => \$opt_inline,
'excel!'    => \$opt_excel,
'reload!'   => \$opt_reload,
'deploy!'   => \$opt_deploy,
'recover=s' => \$opt_recover,
'restore=s' => \$opt_restore,
'env=s'     => \$opt_env,
'validate!' => \$opt_validate
) or die "Incorrect Usage!\n";

if ($opt_help){
    Usage();
}
if (not lockExists()){
	createLock($$);	
}
if (lockExists()){
	if (getCurrentLockPID() != $$ and kill(0,getCurrentLockPID())){
		#enqueueToWaiting($$);
		while(getCurrentLockPID() != $$){
			print STDOUT "Waiting on another running instance: pid(".getCurrentLockPID().")\n";
			sleep(3);
		}
		#dequeueFromWaiting($$);
		if (scalar(@waitq) == 0){
			unlink $waitfile;	
		}
	}
}
if ($opt_env){
   	$envProvided = 1; 
	open (ENVS, $envsfile) or die "Error opening the environments.conf file: $!\n";
	my @envs = <ENVS>;
	close (ENVS);
	foreach (@envs){
		if(/^[^"#"]/){
            		($env,$servlist,$svndirectory) = split(/\s+/);
            		if ($env eq $opt_env){
                		$serverList = $servlist;
                		$svndir = $svndirectory;
                		$envname = $env;
			}
		}
	}
	if (not $envname){
		print STDERR "Error: No such Environment.\n";	
    		unlink $lockfile;;
		exit(1);
	}
}
if (not $envProvided){
    
    my $defaultdirective;
    open (ENVS, $envsfile) or die "Error opening the environments.conf file: $!\n";
    my @envs = <ENVS>;
    close (ENVS);
	foreach(@envs){
        	if(/^[^"#"]/){
        		if (/default=/i){
                		($defaultdirective,$defaultenv) = split(/=/);
                		chomp($defaultenv);
            		}
        	}
	}
    
    open (ENVS, $envsfile) or die "Error opening the environments.conf file: $!\n";
    my @envs = <ENVS>;
    close (ENVS);
    foreach(@envs){
		if(/^[^"#"]/){
                ($env,$servlist,$svndirectory) = split(/\s+/);
				chomp($env);
				chomp($servlist);
				chomp($svndirectory);
                		if ($env eq $defaultenv){
                    			$serverList = $servlist;
                    			$svndir = $svndirectory;
                   			$envname = $env;
                		}
        	}
	}
	if (not $envname){
                print STDERR "Error: default environment doesn't exist.\n";
    		unlink $lockfile;
                exit(1);
        }
}
open (ENVS, $envsfile) or die "Error opening the environments.conf file: $!\n";
my @envs = <ENVS>;
close (ENVS);
foreach(@envs){
                if(/^[^"#"]/){
                        if (/production=/i){
                                ($productiondirective,$prod_env) = split(/=/);
                                chomp($prod_env);
                        }
                }
        }
our $isProdEnv = 0;
if ($prod_env eq $envname){
	$isProdEnv = 1;
}

our $baseDir         = $svndir."/virtual_hosts";
our $dbmDir          = $baseDir."/dbm";
our $domainsDir      = $baseDir."/domains";
our $micrositesDir   = $baseDir."/microsites";

if ($opt_deploy and $opt_reload){
    print STDERR "ERROR: You can't reload while deploying.\n";
    unlink $lockfile;
    exit(1);
}
if ($opt_inline and not $opt_bulk){
	print STDERR "Error: You can't specify [--inline] without [--file].\n";
	unlink $lockfile;
	exit(1);
}
if ($opt_excel and not $opt_bulk){
	print STDERR "Error: You can't specify [--excel] without [--file].\n";
	unlink $lockfile;
	exit(1);
}
if ($opt_excel and $opt_inline){
	print STDERR "Error: You can't specify [--excel] with [--inline].\n";
	unlink $lockfile;
	exit(1);
}
if ($opt_restore and $opt_recover){
	print STDERR "Can't invoke --restore with --recover\n";
    	unlink $lockfile;
	exit(1);
}
if ($opt_restore and $opt_deploy){
	print STDERR "Can't invoke --restore with --deploy because --deploy updates to the SVN head\n";
    	unlink $lockfile;
	exit(1);
}
if ($opt_restore and (scalar(@ARGV) > 0)){
	print STDERR "Error: can't invoke the restore option with other options\n";
}elsif($opt_restore and (scalar(@ARGV) == 0 )){
	$isRestore = 1;
	restoreToRevision($opt_restore);
}
if ($opt_deploy){
    print STDOUT "Updating repository to the latest revision\n";
    system ("cd $svndir ; svn update --username $svnuser --password $svnpass");
}
if ($opt_recover and (scalar(@ARGV) == 0)){
	$isRecover = 1;
 	return recoverConf($opt_recover);
}elsif($opt_recover and (scalar(@ARGV) > 0)){
	print STDERR "The recover option should be provided alone\n";
    	unlink $lockfile;
	exit(1);
}
if ($opt_bulk){
	$isBulk = 1;
        if (not ($opt_inline or $opt_excel)){
    		($username, $password, $ruleType, @domains) = @ARGV;
        }elsif ($opt_inline or $opt_excel){
            ($username, $password) = @ARGV;
        }
	$UserName = authenticate($username,$password);
    foreach my $domain (@domains){
        $orig_domain = $domain;
        if ($domain =~ /(\S+).emc.com/){
            my $filename = getDomainConfFile($1);
            if ($isLocale){
                $domain = $1;
                $isLocale = 0;
            }
            $filename = getDomainConfFile($orig_domain);
            if ($isMicrosite){
                $domain = $orig_domain;
                $isMicrosite = 0;
            }
        }
    }
	bulkProcess($opt_bulk);
    if ($opt_validate and not $opt_deploy){
        validateRules();
    }
}
if ($opt_deploy and (scalar(@ARGV) == 0)){
	if ($opt_email and not $opt_silent){
		$opt_email = 1;
	}
    my $commitmsg = "Automated Deployment on ".scalar(localtime(time +0));
    system("cp -R $svndir $absolute_path.uwconf");
    system("find $absolute_path.uwconf -type d -name .svn | xargs rm -Rf &> /dev/null");
    system("cd $absolute_path ; tar cfvz uwconf.tar.gz .uwconf &> /dev/null");
    system("rm -Rf $absolute_path.uwconf");
    print STDOUT "Commiting this change to SVN\n";
    `cd $svndir ; svn --username $svnuser --password $svnpass commit -m "$commitmsg"`;
    my $errno = updateServers();
    system("rm -Rf $absolute_path/uwconf.tar.gz");
    unlink $lockfile;
    exit($errno);
}
if ($opt_reload){
    reloadServers();
    		unlink $lockfile;
	exit(0);
}
if ($opt_delete){
    $isDelete = 1;
    ( $username,$password,$srcURI,@domains) = @ARGV;
}elsif (not $opt_bulk){
    ($username,$password,$srcURI,$dstURI,$ruleType,@domains) = @ARGV;
    $origin_dstURI = $dstURI;
    $ruleType =~ tr/[A-Z]/[a-z]/;
}
if ($opt_version){
	print $VERSION."\n";
    		unlink $lockfile;
	exit(0);
}
if (scalar @ARGV != 0){
	$UserName = authenticate($username,$password);
}
if (not $isBulk){
    validateInput();
    foreach (@domains){
        if ($isDelete){
            deleteFromLocale($_);
            deleteFromMicrosite($_);
        }else{
            my $status = updateRule($_);
            if ($status == 0){
                insertRule($_);
            }
        }
        if ($isLocale){
            push(@ListOfRules, $srcURI." ".$dstURI." ".$ruleType." ".$_.".emc.com");
        }elsif ($isMicrosite){
            push(@ListOfRules, $srcURI." ".$dstURI." ".$ruleType." ".$_);
        }
        
        $ruleExisting = 0;
        $isMicrosite = 0;
        $isLocale = 0;
    }
    if ($opt_validate and not $opt_deploy){
        validateRules();
    }
}
if ($opt_deploy and (scalar(@ARGV) > 0)){
	if (not $opt_silent){
        $opt_email = 1;
    }
	my $commitmsg = "rewrite rules automated transaction on ".scalar(localtime(time +0));
	system("cp -R $svndir $absolute_path.uwconf");
    system("find $absolute_path.uwconf -type d -name .svn | xargs rm -Rf &> /dev/null");
	system("cd $absolute_path ; tar cfvz uwconf.tar.gz .uwconf &> /dev/null");
	system("rm -Rf $absolute_path.uwconf");
	print STDOUT "Commiting this change to SVN\n";
	`cd $svndir ; svn  --username $svnuser --password $svnpass commit -m "$commitmsg"`;
	updateServers();
    system("rm -Rf $absolute_path/uwconf.tar.gz");
}
if ($opt_silent){
	$opt_email = 0;
}
if ($opt_email){
    mailer();
}
unlink $lockfile, $waitfile;

sub createLock{
    
	my $pid = $_[0];
	my $retval = kill(0,$pid);
	if ($retval){
        open(LCKFILE,">",$lockfile) or die "Can't create a lock file: $!\n";
        print LCKFILE $pid;
        close(LCKFILE);
	}else{
		unlink($lockfile);
	}
	return $retval;
}

sub lockExists{
    
	my $retval = open(LCKFILE,$lockfile);
	close (LCKFILE);
	return $retval;
}

sub enqueueToWaiting{
    
	my $pid = $_[0];
	my $retval = open(WAITFILE,">>",$waitfile) or die "Can't create a process waiting list file: $!\n";
	print WAITFILE $pid."\n";
	close(WAITFILE);
	open(WAITFILE,$waitfile) or die "Can't create a process waiting list file: $!\n";
    @waitq = <WAITFILE>;
    close(WAITFILE);
    foreach(@waitq){
        chomp;
        if ($_ == $pid){
			return 1;
        }
    }
	return 0;
}

sub dequeueFromWaiting{
    
	my $pid = $_[0];
	my $retval = open(WAITFILE,$waitfile) or die "Can't open the process waiting list file: $!\n";
	@waitq = <WAITFILE>;
    close(WAITFILE);
	foreach(@waitq){
		if ($_ == $pid){
			$_ = "";
		}
	}
	$retval = open(WAITFILE,">",$waitfile) or die "Can't create a process waiting list file: $!\n";
    print WAITFILE @waitq;
    close(WAITFILE);
    
	foreach(@waitq){
		if ($_ == $pid){
			return 0;
		}
	}
	return 1
}

sub getCurrentLockPID{
    
	if (lockExists()){
		open(LCKFILE,$lockfile) or die "Couldn't get lock PID from lock file: $!\n";
		my $pid = <LCKFILE>;
		close(LCKFILE);
		chomp($pid);
		if (kill(0,$pid)){
			return $pid;
		}else{
			unlink $lockfile;
		}
	}else{
		createLock($$);
	}
    
}

sub getCurrentWaitingPID{
    
	open(WAITFILE,$waitfile) or die "Can't open the process waiting list file: $!\n";
    @waitq = <WAITFILE>;
    close(WAITFILE);
	return $waitq[0];
}

sub validateInput{

	if ($srcURI eq "/"){
        print STDERR "Error: you can't change the root URI\n";
        unlink $lockfile;
        exit (1);
	}
	if ($srcURI =~ /^\/+\/$/){
		print STDERR "Error: Invalid rule source target!\n";
        unlink $lockfile;
		exit(1);
	}
	if ((not ($opt_inline or $opt_excel)) and (substr($srcURI,0,1) ne "/")){
        print STDERR "Error: Invalid rule source target!\n";
        unlink $lockfile;
        exit(1);
    }elsif ($opt_inline or $opt_excel){
		if ($srcURI =~ /^https?:\/\//i){
			$srcURI =~ s/https?:\/\///;
			$srcURI =~ s/([^\/]*)\//\//;
			my $domain = $1;
			$domains[0] = $domain;
			undef $domain;
		}else{
			$srcURI =~ s/([^\/]*)\//\//;
			my $domain = $1;
			$domains[0] = $domain;
			undef $domain;
		}
	}
	if (substr($srcURI,-1) eq "/"){
        $srcURI = $srcURI."index.htm";
	}
    if (not $isDelete){
        if ($ruleType ne "vanity"){
            if($ruleType ne "redirect"){
                print STDERR "Error: Rule type is invalid!\n";
                unlink $lockfile;
                exit(1);
            }
        }
        if ($ruleType eq "vanity"){
            
            if (scalar(@domains) > 1 and substr($dstURI,0,1) ne "/" ){
                print STDERR "Error: you can't set a vanity rule for multiple domains with a fixed domain name in the destination\n";
                unlink $lockfile;
                exit(1);
            }
            
            if (substr($dstURI,0,1) ne "/"){
        		$dstURI =~ s/^https?\:\/\///;
                
                if (grep {/\Q$domains[0]\E/} $dstURI){
	        		$dstURI =~ s/^(\w+\.)(\w+\.)?(\w+)//;
                }else{
                    $dstURI = $origin_dstURI;
                    $ruleType = "redirect";
                }
            }
            
        	if ($dstURI eq "" or $dstURI eq "/"){
                $dstURI = $origin_dstURI;
                $ruleType = "redirect";
    		}
        }
        if (substr($dstURI,0,4) ne "http"){
        	if (substr($dstURI,0,1) ne "/"){
                $dstURI = "http://".$dstURI;
                #print STDERR "Error: Invalid rule destination target!\n";
                #unlink $lockfile;
                #exit(1);
        	}
        }
        if ($dstURI =~ /^\/+\/$/){
        	print STDERR "Error: Invalid rule destination target!\n";
    		unlink $lockfile;
        	exit(1);
        }
    }
    if (scalar(@domains) == 0){
        print STDERR "Error: No domains are selected for this rule!\n";
        unlink $lockfile;
        exit(1);
    }elsif(scalar(@domains) > 1){
        foreach (@domains){
            if (/global/i){
                print STDERR "Error: can't specify global with other domains\n";
                unlink $lockfile;
                exit(1);
            }
        }
    }
    
    foreach my $domain (@domains){
        $orig_domain = $domain;
        if ($domain =~ /(\S+).emc.com/){
            my $filename = getDomainConfFile($1);
            if ($isLocale){
                $domain = $1;
                $isLocale = 0;
            }
            $filename = getDomainConfFile($orig_domain);
            if ($isMicrosite){
                $domain = $orig_domain;
                $isMicrosite = 0;
            }
        }
    }
}

sub validateRules{
    
    htmlheader();
    
    my $src;
    my $dst;
    my $type;
    my $domain;
    my @SrcCurlOut;
    my @DstCurlOut;
    my $curl_src_http_code;
    my $curl_dst_http_code;
    my $curl_redir_loc;
    my $status;
    
    
    print "\n                          Validating rules manipulated by $UserName\n";
    print "                       **************************************************\n";
    
    foreach(@ListOfRules){
        
        ($src,$dst,$type,$domain) = split(/\s/);
        chomp($src);
        chomp($dst);
        chomp($type);
        chomp($domain);
	
        if (substr($src,0,1) eq "/"){
            $src = "http://".$domain.$src;
        }
        
        if (substr($dst,0,1) eq "/"){
            $dst = "http://".$domain.$dst;
        }
        
        @SrcCurlOut = `curl -I $src 2> /dev/null`;
        foreach (@SrcCurlOut){
            tr/\r/\n/;
            if ($_ =~ /HTTP\/1\.1\s(...)/){
                $curl_src_http_code = $1;
                chomp($curl_src_http_code);
            }
            
            if ($_ =~ /Location:\s(.*)/){
                $curl_redir_loc = $1;
                chomp($curl_redir_loc);
            }
        }
        
        @DstCurlOut = `curl -I $dst 2> /dev/null`;
        foreach (@DstCurlOut){
            tr/\r/\n/;
            if ($_ =~ /HTTP\/1\.1\s(...)/){
                $curl_dst_http_code = $1;
                chomp($curl_dst_http_code);
            }
        }
        
        if ($type eq "vanity"){
            if ($curl_src_http_code eq "200" and $curl_dst_http_code eq "200"){
                $status = "PASS";
            }else{
                $status = "FAIL";                
            }
            logger($logtype{'validation'},$src,$dst,$type,$domain,$curl_src_http_code,$curl_dst_http_code,$curl_redir_loc,$status);
        }
        
        if ($type eq "redirect"){
            if ($curl_src_http_code eq "301"){
                if ($curl_redir_loc eq $dst){
                    $status = "PASS";
                }else{
                    $status = "FAIL";
                }
            }else{
                $status = "FAIL";
            }
            
            logger($logtype{'validation'},$src,$dst,$type,$domain,$curl_src_http_code,$curl_dst_http_code,$curl_redir_loc,$status);
        }
        
        push(@ValidationEmailMessage,"<li>Source: ".$src."</li>");
        push(@ValidationEmailMessage,"<li>Target: ".$dst."</li>");
        push(@ValidationEmailMessage,"<li>Source HTTP Code: <b>".$curl_src_http_code."   </b>Target HTTP Code: <b>".$curl_dst_http_code."</b></li>");
        push(@ValidationEmailMessage,"<li>Rule Type: <b>".$type."</b></li>");
        if ($status eq "PASS"){
            push(@ValidationEmailMessage,"<li>Status: <font color='#00FF00'><b><i>".$status."</i></b></font><p>.</p></li>");
        }elsif ($status eq "FAIL"){
            push(@ValidationEmailMessage,"<li>Status: <font color='#FF0000'><b><i>".$status."</i></b></font><p>.</p></li>");

        }
    }
    htmlfooter();
}

sub trim($){
    
    my $string = shift;
    $string =~ s/^\s+//;
    return $string;
}

sub getDomainConfFile{
    
    my $domainName = shift;
    opendir(LOCALESDIR,$dbmDir) or die "Error opening the locales rewrites directory: $!";
    my @LocalesFileNames = readdir LOCALESDIR;
    closedir LOCALESDIR;
    
    foreach (@LocalesFileNames){
        $_ =~ s/.txt//;
        $_ =~ s/^\.\.?//;
    }
    opendir(MICRODIR,$micrositesDir) or die "Error opening the microsites rewrites directory: $!";
    my @MicrositesFileNames = readdir MICRODIR;
    closedir MICRODIR;
    
    foreach (@MicrositesFileNames){
        $_ =~ s/^\.\.?//;
    }
    if (grep {/\Q$domainName\E/} @LocalesFileNames){
        $isLocale = 1;
	if ($ruleType eq "redirect"){
		if ($domains[0] eq "global"){
			return $dbmDir."/global_redirects.txt";
		}else{
        		return $dbmDir."/".$domainName.".txt";
		}
	}elsif ($ruleType eq "vanity"){
		if ($domains[0] eq "global"){
                	return $dbmDir."/v-global_redirects.txt";
        	}else{
                	return $dbmDir."/"."v-".$domainName.".txt";
        	}
	}
    }
    elsif (grep {/\Q$domainName\E/} @MicrositesFileNames){
        $isMicrosite = 1;
        return $micrositesDir."/".$domainName;
    }
}

sub dstHasSpecialChar{
    
    my $hasSpecial;
    if (grep {/\'#'/} $dstURI or
    grep {/\?/} $dstURI or
    grep {/\!/} $dstURI or
    grep {/\&/} $dstURI or
    grep {/\'#'/} $srcURI or
    grep {/\?/} $srcURI or
    grep {/\!/} $srcURI or
    grep {/\&/} $srcURI){
    $hasSpecial = 1;
    }else{
        $hasSpecial = 0;
    }
    return $hasSpecial;
}

sub composeOptions{
    
    my $src = $srcURI;
    my $dst = $dstURI;
    my $type = $ruleType;
    my ($optL,$optR,$optCO,$optNC,$optNS,$optNE,$optPT,$cookieDomain) = qw(L R=301 CO NC NS NE PT .emc.com);
    my ($vanity,$reDir) = qw(vanity reDir);
    my $hasSpecial = dstHasSpecialChar();
    
    if ($isMicrosite){
        if ($type eq "redirect"){
            if ($hasSpecial){
                return "[$optL,$optR,$optNE,$optNC]";
            }else{
                return "[$optL,$optR,$optNC]";
            }
            
        }elsif ($type eq "vanity"){
            if ($hasSpecial){
                return "[$optL,$optR,$optNE,$optNC]";
            }else{
                return "[$optL,$optR,$optNC]"
            }
        }
        
    }elsif ($isLocale){
        if ($type eq "redirect"){
            if ($hasSpecial){
                return "[$optL,$optR,$optNC,$optNE,$optCO=$reDir:$src:$cookieDomain]";
            }else{
                return "[$optL,$optR,$optNC,$optCO=$reDir:$src:$cookieDomain]";
            }
            
        }elsif ($type eq "vanity"){
            if ($hasSpecial){
                return "[$optL,$optPT,$optNS,$optNC,$optNE,$optCO=$vanity:$dst:$cookieDomain]";
            }else{
                return "[$optL,$optPT,$optNS,$optNC,$optCO=$vanity:$dst:$cookieDomain]";
            }
        }
    }
}

sub updateRule{
    
    my $domain = shift;
    my $old_to;
    my $logoptions;
    my @ReadyRules;
    my $conf_file = getDomainConfFile($domain);
    open(CONFFILE,$conf_file) or die "Error opening file $conf_file for reading: $!";
    my @AllRules = <CONFFILE>;
    close CONFFILE;
    
    foreach (@AllRules){
        push(@ReadyRules, trim($_));
    }
    
    if ($isMicrosite){
        foreach (@ReadyRules){
            my ($ModRewriteDirective,$From,$To,$Options) = split(/\s+/);
            
            if (/^[^"#"]/){
                if (grep {/^\^\Q$srcURI\E$/i} $From or
                grep {/^\^\Q$srcURI\E\/\*\$/i} $From or
                grep {/^\^\Q$srcURI\E\$/i} $From){
                    $ruleExisting = 1;
                    $old_to = $To;
                    if ($ruleType eq "vanity"){
                        $To = $origin_dstURI;
                    }elsif ($ruleType eq "redirect"){
                        $To = $dstURI;
                    }
                }
                $_ = $ModRewriteDirective."  ".$From."  ".$To."  ".$Options."\n";
            }
        }
    }
    
    if ($isLocale){
            foreach (@ReadyRules){
                my ($From,$To) = split(/\s+/);
                
                if (/^[^"#"]/){
                    if (grep {/^\Q$srcURI\E$/i} $From){
                        $ruleExisting = 1;
                        $old_to = $To;
                        $To = $dstURI;
                    }
                }
                $_ = $From."  ".$To."\n";
            }
    }
    @ExportedRules = @ReadyRules;
    
    if ($ruleExisting){
        open(CONFFILE,'>',$conf_file) or die "Error opening file for writing: $!";
        print CONFFILE @ReadyRules;
        push (@EmailMessage, "Update for rule ".$srcURI." on domain ".$domain."\n");
	if ($isProdEnv){
        	logger($logtype{'update'}, $srcURI,$dstURI,$ruleType,$logoptions,$domain,$old_to);
	}
        close CONFFILE;
    }
    undef @ReadyRules;
    return $ruleExisting;
}

sub insertRule{
    
    my $domain = shift;
    my $newRule;
    my $options;
    my $conf_file = getDomainConfFile($domain);
    open(CONFFILE,'>',$conf_file) or die "Error opening file $conf_file for writing: $!";
    if ($isMicrosite){
        if ($ruleType eq "vanity"){
            $options = composeOptions($srcURI,$dstURI,$ruleType);
            $newRule = "RewriteRule  ^".$srcURI.'$'."  ".$origin_dstURI."  ".$options;
        }elsif ($ruleType eq "redirect"){
            $options = composeOptions($srcURI,$dstURI,$ruleType);
            $newRule = "RewriteRule  ^".$srcURI.'$'."  ".$dstURI."  ".$options;
        }
        foreach (@ExportedRules){
            $_ =~ s/<\/VirtualHost>//;
        }
        push(@ExportedRules, $newRule."\n");
        push (@ExportedRules, "</VirtualHost>");
        
    }elsif ($isLocale){
            $newRule = $srcURI."  ".$dstURI;
            push(@ExportedRules, $newRule);
    }
    
    print CONFFILE @ExportedRules;
    push (@EmailMessage, "Insert for rule ".$srcURI." on domain ".$domain."\n");
    if ($isProdEnv){
    	logger($logtype{'insert'}, $srcURI,$dstURI,$ruleType,$options,$domain);
    }
    undef @ExportedRules;
    close CONFFILE;
}

sub deleteRule{
    
    my $domain = shift;
    my $conf_file = getDomainConfFile($domain);
    my @ReadyRules;
    
    open(CONFFILE,$conf_file) or die "Error opening file $conf_file for reading: $!";
    my @AllRules = <CONFFILE>;
    close CONFFILE;
    
    foreach (@AllRules){
        push(@ReadyRules, trim($_));
    }
    
    if ($isMicrosite){
        
        foreach (@ReadyRules){
            my ($ModRewriteDirective,$From,$To,$Options) = split(/\s+/);
            
            if (/^[^"#"]/){
                if (grep {/^\^\Q$srcURI\E$/i} $From or grep {/^\^\Q$srcURI\E\/\*\$/i} $From or grep {/^\^\Q$srcURI\E\$/i} $From){
                    $ruleExisting = 1;
                    push (@EmailMessage, "Delete for rule ".$srcURI." on domain ".$domain."\n");
                    $_ = "";
                }
            }
        }
    }
    
    if ($isLocale){
        
        foreach (@ReadyRules){
            my ($From,$To) = split(/\s+/);
            
            if (/^[^"#"]/){
                if (grep {/^\Q$srcURI\E$/i} $From){
                    $ruleExisting = 1;
		    if ($ruleType eq "redirect"){
                    	push (@EmailMessage, "Delete for redirect rule ".$srcURI." on domain ".$domain."\n");
		    }elsif($ruleType eq "vanity"){
                    	push (@EmailMessage, "Delete for vanity rule ".$srcURI." on domain ".$domain."\n");
                    }
                    $_ = "";
                }
            }
        }
    }
    
	if ($ruleExisting){
		open(CONFFILE,'>',$conf_file) or die "Error opening file $conf_file for writing: $!";
        	print CONFFILE @ReadyRules;
		if ($isProdEnv){
        		logger($logtype{'delete'},$srcURI,$domain);
		}
        	close CONFFILE;
		if ($ruleType eq "redirect"){
			print "Redirect rule deleted on domain: $domain\n";
                    }elsif($ruleType eq "vanity"){
			print "Vanity rule deleted on domain: $domain\n";
                    }
		$ruleExisting = 0;

	}else{
		    if ($ruleType eq "redirect"){
                        print "Redirect rule NOT found on domain: $domain\n";
                    }elsif($ruleType eq "vanity"){
                        print "Vanity rule NOT found on domain: $domain\n";
                    }
                        
	}
    
}

sub deleteFromLocale{
    
	my $domain = shift;
	$ruleType = "redirect";
    my $tempfile = getDomainConfFile($domain);
    if ($isLocale){
        deleteRule($domain);
    }
    
	$ruleType = "vanity";
	$tempfile = getDomainConfFile($domain);
	if ($isLocale){
		deleteRule($domain);
        
	}
	$ruleType = "";
}

sub deleteFromMicrosite{
    
	my $domain = shift;
	$ruleType = "redirect";
	my $tempfile = getDomainConfFile($domain);
	if ($isMicrosite){
        deleteRule($domain);
	}
	$ruleType = "";
}

sub authenticate{
    
    my $username = $_[0];
    my $password = $_[1];
    my $salt = '*FAKESALT*';
    my $digest = crypt($password,$salt);
    my $loginSuccessfull = 0;
    my $userdb = $rrms_confdir."accounts";
    
    open(PASSFILE,$userdb);
    my @USERS = <PASSFILE>;
    close PASSFILE;
    
    foreach (@USERS){
        chomp;
        my ($retUser,$fullName,$retPass) = split(/:/);
        
        if (/\Q$username\E/ eq /\Q$retUser\E/ and /\Q$digest\E/ eq /\Q$retPass\E/){
            $loginSuccessfull = 1;
            return $fullName;
        }
    }
    foreach (@domains){
        $concatDomains .= " ".$_;
    }
    if (not $loginSuccessfull){
        logger($logtype{'security'},$concatDomains,$username);
        print STDERR "Access Denied\n";
    		unlink $lockfile;
        exit(1);
    }
}

sub logger($ @){
    
    my ($mode, @data) = @_;
    my $vsrc;
    my $vdst;
    my $vtype;
    my $vdomain;
    my $vcurl_src_http_code;
    my $vcurl_dst_http_code;
    my $vcurl_redir_loc;
    my $vstatus;
    my $from;
    my $to;
    my $rule_type;
    my $options;
    my $domain;
    my $transtype;
    my $old_dst;
    my $timestamp = scalar(localtime(time + 0));
    my $logfile = $rrms_logsdir."rules.log";
    
    
    if ($mode == $logtype{'validation'}){
            $vsrc = $data[0];
            $vdst = $data[1];
            $vtype = $data[2];
            $vdomain = $data[3];
            $vcurl_src_http_code = $data[4];
            $vcurl_dst_http_code = $data[5];
            $vcurl_redir_loc = $data[6];
            $vstatus = $data[7];
        
            open(VALIDATION,">".'-') or die "Error appending to stdout: $!";
            write(VALIDATION);
            close(VALIDATION);
        
    }else{
    
            $from = $data[0];
            $to = $data[1];
            $rule_type = $data[2];
            $options = $data[3];
            $options = "N.A" if $isLocale;
            $domain = $data[4];
    }
    

    if ($mode == $logtype{'insert'}){
        $transtype = "NEW";
        undef $old_dst;
        open(LOGFILEINS,">>",$logfile) or die "Error openning the log file: $!";
        write(LOGFILEINS);
        close(LOGFILEINS);
    }elsif ($mode == $logtype{'update'}){
        $transtype = "UPDATE";
        $old_dst = $data[5];
        open(LOGFILEUPD,">>",$logfile) or die "Error openning the log file: $!";
        write(LOGFILEUPD);
        close(LOGFILEUPD);
    }elsif ($mode == $logtype{'security'}){
        $domain = $data[0];
	if ($isDelete){
            $origin_dstURI = "DELETE ATTEMPT";
            $ruleType = "N.A";
        }
        open(LOGSECURITY,">>",$logfile) or die "Error openning the log file: $!";
        write(LOGSECURITY);
        close(LOGSECURITY);
    }elsif ($mode == $logtype{'delete'}){
	$domain = $data[1];
	$transtype = "DELETE";
	open(LOGFILEDEL,">>",$logfile) or die "Error openning the log file: $!";
        write(LOGFILEDEL);
        close(LOGFILEDEL);
	
    }

    
 format VALIDATION =
 -----------------------------------------------------------------------------------------------------------------------------------------------------
 Source: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $vsrc
 Target: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $vdst
 Source HTTP Code: @<<<<  Target HTTP Code: @<<<<
 $vcurl_src_http_code,$vcurl_dst_http_code
 Rule Type: @<<<<<<<<
 $vtype
 Status: @<<<<<
 $vstatus
.

 format LOGFILEUPD =
 ===== START RULE ==================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 $transtype
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $from
 To:   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $to
 Rule Type: @<<<<<<<<<
 $rule_type
 mod_rewrite options: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $options
 Old Destination: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $old_dst
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $UserName
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $timestamp
 ===== END RULE ====================================================================================================================================
.
    
 format LOGFILEINS =
 ===== START RULE ==================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 $transtype
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $from
 To:   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $to
 Rule Type: @<<<<<<<<<
 $rule_type
 mod_rewrite options: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $options
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $UserName
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $timestamp
 ===== END RULE ====================================================================================================================================
.
    
format LOGFILEDEL =
 ===== START RULE ==================================================================================================================================
 Domain: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 Transaction type: @<<<<<<<
 $transtype
 Rule: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $from
 User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $UserName
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $timestamp
 ===== END RULE ====================================================================================================================================
.

 format LOGSECURITY =
 <><><><><> START SECURITY ALERT <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
 Domain(s): @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $domain
 From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $srcURI
 To:   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $origin_dstURI
 Rule Type: @<<<<<<<<<
 $ruleType
 Attempted User: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $username
 Timestamp: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
 $timestamp
 <><><><><> END SECURITY ALERT <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><
.
}

sub mailer{

    my $mailer = "/usr/sbin/sendmail -t";
	my $email = "";
    my $vemail = "";
    
    
    foreach (@EmailMessage){
		$email .= $_."\n";
	}
    #open(MAIL,"|$mailer") or die "Error opening the sendmail program: $!\n";
    #write(MAIL);
    #close(MAIL);
    
    if ($opt_validate){
        foreach(@ValidationEmailMessage){
            $vemail .= $_."\n";
        }
        open(VMAIL,"|$mailer") or die "Error opening the sendmail program: $!\n";
        write(VMAIL);
        close(VMAIL);
    }
    
format VMAIL =
From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$localemail
To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
"$mail_addresses{UW},$mail_addresses{Khaled}"
Subject: Rewrite rules report
Mime-Version: 1.0
Content-Type: text/html; charset=us-ascii
Content-Transfer-Encoding: quoted-printable
    
@*
$vemail
.
    
format MAIL =
From: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$localemail
To: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
"$mail_addresses{Khaled}"
Subject: Rewrite Rules Transaction
Mime-Version: 1.0
Content-Type: text/html; charset=us-ascii
Content-Transfer-Encoding: quoted-printable

The below action(s) were performed on env @<<<<<<<<<<< by user: @<<<<<<<<<<<<<<<<<<<<<<<<<<
$envname, $UserName
---------------------------------------------------------------------------------
@* 
$email
.

}

sub serverError{
    
    my $servername = $_[0];
    my $msgid = $_[1];
    my $timestamp  = scalar(localtime(time + 0));
    
    my %msg = (
    1  => "Error uploading the tarball file uwconf.tar.gz to $servername",
    2  => "Failed to extract uwconf.tar.gz on $servername",
    3  => "Failed to create the backup directory on $servername",
    4  => "Failed to backup the current conf on $servername",
    5  => "Failed to stop the Apache server on $servername",
    6  => "Failed to remove the current conf file on $servername",
    7  => "Failed to copy from the uploaded uwconf.tar.gz to the conf dir on $servername",
    8  => "Error compiling rules to DBM files on $servername",
    9  => "Error starting the Apache server on $servername",
    10 => "Error executing the post cleaning procedure on $servername",
    11 => "Error updating servers to SVN revision: "
    );
    
    my $serverLog  = $rrms_logsdir."servers.log";
    open (SERVLOG,">>",$serverLog) or die "Can't open the servers log file: $!\n";
    print SERVLOG $timestamp - $msg{$msgid}."\n";
    close (SERVLOG);
    print  STDERR "\n".$msg{$msgid}." [ Terminating Process ]\n";
    
}

sub updateServers{
    
    my $username;
	my $server;
	my $errno;
    
	open (SERVLST,$serverList) or die "Can't open the servers list file: $!\n";
	my @SERVERS = <SERVLST>;
	close (SERVLST);
	
	foreach (@SERVERS){
	($username,$server) = split(/@/);
	chomp($username);
        chomp($server);
        if ($username eq "root"){
		$SUDO = "";
	}
        print "=================================================\n";
        print "Manipulating server $server\n";
        print "=================================================\n";
        print STDOUT "Uploading SVN content ";
        $errno = system("scp -q $absolute_path/uwconf.tar.gz  $username\@$server:/tmp");
        if ($errno != 0){
            serverError($server,1);
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Extracting SVN content ";
        $errno = system("ssh -q $username\@$server 'tar xfvz /tmp/uwconf.tar.gz &> /dev/null'");
        if ($errno != 0){
            serverError($server,2);
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Checking / Creating backup directory ";
        $errno = system("ssh -q $username\@$server 'mkdir -p ~/conf_bkp'");
        if ($errno != 0){
            serverError($server,3);
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Backing up the current Apache configurations ";
        $errno = system("ssh -q $username\@$server 'cd ~/conf_bkp  ; tar cfvz conf-`date +%d-%m-%Y`.tar.gz /etc/httpd/conf &> /dev/null'");
        if ($errno != 0){
            serverError($server,4);
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Stopping the Apache server ";
        $errno = system("ssh -q $username\@$server '$SUDO /sbin/service httpd stop &> /dev/null'");
        if ($errno != 0){
            serverError($server,5);
    		unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Deleting the current Apache configurations ";
        $errno = system("ssh -q $username\@$server 'rm -Rf /etc/httpd/conf/* &> /dev/null'");
        if ($errno != 0){
            serverError($server,6);
            print STDOUT "Restoring the Apache configuration directory from backup.\n";
            system("ssh -q $username\@$server 'cd / ; tar xfvz ~/conf_bkp/conf-`date +%d-%m-%Y`.tar.gz &> /dev/null'");
            print STDOUT "Recovering the Apache instance status.\n";
            system("ssh -q $username\@$server '$SUDO /sbin/service httpd start'");
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Copying SVN to Apache ";
        $errno = system("ssh -q $username\@$server 'cp -R ~/.uwconf/* /etc/httpd/conf/ &> /dev/null'");
        if ($errno != 0){
            serverError($server,7);
            print STDOUT "Restoring the Apache configuration directory from backup.\n";
            system("ssh -q $username\@$server 'rm -Rf /etc/httpd/conf/* &> /dev/null'");
            system("ssh -q $username\@$server 'cd / ; tar xfvz ~/conf_bkp/conf-`date +%d-%m-%Y`.tar.gz'");
            print STDOUT "Recovering the Apache instance status.\n";
            system("ssh -q $username\@$server '$SUDO /sbin/service httpd start'");
            unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Compiling rules to DBM files ";
        $errno = system("ssh -q $username\@$server 'cd /etc/httpd/conf/virtual_hosts/dbm ; for i in *txt ; do /usr/sbin/httxt2dbm -i \$i  -o `echo \$i | cut -d \"\.\" -f 1`.map ; done &> /dev/null'");
        if ($errno != 0){
            serverError($server,8);
            print STDOUT "Restoring the Apache configuration directory from backup.\n";
            system("ssh -q $username\@$server 'cd / ; tar xfvz ~/conf_bkp/conf-`date +%d-%m-%Y`.tar.gz'");
            print STDOUT "Recovering the Apache instance status.\n";
            system("ssh -q $username\@$server '$SUDO /sbin/service httpd start'");
       	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Starting the Apache server ";
        $errno = system("ssh -q $username\@$server '$SUDO /sbin/service httpd start &> /dev/null'");
        if ($errno != 0){
            serverError($server,9);
            print "Retrying....";
            system("ssh -q $username\@$server '$SUDO /sbin/service httpd start'");
    	    unlink $lockfile;
            exit(1);
        }
        print "[ OK ]\n";
        
        print STDOUT  "Cleaning up ";
        $errno = system("ssh -q $username\@$server 'rm -Rf ~/.uwconf /tmp/uwconf.tar.gz &> /dev/null'");
        if ($errno != 0){
            serverError($server,10);
        }
        print "[ OK ]\n";
    }
    if ($opt_validate){
        validateRules();
    }
	return $errno;
}

sub reloadServers{
	
    my $serverLog  = $rrms_logsdir."servers.log";
    my $username;
    my $server;
    my $reloadCMD  =  $SUDO.' /sbin/service httpd reload';
    my $timestamp  = scalar(localtime(time + 0));
    my $errno;
    
    open (SERVLST,$serverList) or die "Can't open the servers list file: $!\n";
    my @SERVERS = <SERVLST>;
    close (SERVLST);
    
	foreach (@SERVERS){
		($username,$server) = split(/@/);
		chomp($username);
		chomp($server);
		if ($username eq "root"){
			$reloadCMD = '/sbin/service httpd reload';
		}
		$errno = system("ssh -q  $username\@$server $reloadCMD");
		if ($errno != 0){
			open (SERVLOG,">>",$serverLog) or die "Can't open the servers log file: $!\n";
            		print SERVLOG "Error reloading $server at $timestamp\n";
            		close (SERVLOG);
            		print STDERR "Error reloading server $server\n";
		}
	}
}

sub bulkProcess{
    
    if ($opt_excel){
    my $excel = Spreadsheet::XLSX->new($_[0]);
    my $cell1;
    my $cell2;
    my $cell3;
    my $xlsRtype;
    my $xlsRsrc;
    my $xlsRdst;
    
    foreach my $sheet (@{$excel->{Worksheet}}) {
        $sheet->{MinRow} ||= $sheet->{MaxRow};
        foreach my $row ($sheet->{MinRow} .. $sheet->{MaxRow}) {
            $sheet->{MaxCol} ||= $sheet->{MinCol};
            if ($row != 1){
                $cell1 = $sheet->{Cells}[$row][5];
                $cell2 = $sheet->{Cells}[$row][6];
                $cell3 = $sheet->{Cells}[$row][7];
                if ($cell1){
                    $xlsRsrc = $cell1->value();
                    $xlsRsrc =~ tr/A-Z/a-z/;
                    $xlsRsrc =~ s/\s+$//;
                    if ($cell2){
                        $xlsRdst = $cell2->value();
                        $xlsRdst =~ s/\s+$//;
                        if ($cell3){
			    #$cell3 =~ tr/A-Z/a-z/;
                            if ($cell3->value() =~ /yes/i){
                                $xlsRtype = "vanity";
                            }else{
                                $xlsRtype = "redirect";
                            }
                            push(@blkAll, $xlsRsrc." ".$xlsRdst." ".$xlsRtype."\n");
                        }
                    }
                }
            }
        }
    }
    }elsif (not $opt_excel){
        my $file = $_[0];
        open(BLKFILE,$file) or die "Error opening the raw rules file: $!\n";
        @blkAll = <BLKFILE>;
        close(BLKFILE);
    }
    
	foreach (@blkAll){
            if (not $_ =~ /^\s+$/){
            		$_ =~ s/^\s+//;
			if (not ($opt_inline or $opt_excel)){
                ($srcURI,$dstURI) = split(/\s+/);
			}elsif ($opt_inline or $opt_excel){
				($srcURI,$dstURI,$ruleType) = split(/\s+/);
			}
            
            validateInput();
            
	    	foreach (@domains){
                my $status = updateRule($_);
                if ($status == 0){
                    insertRule($_);
                }
                
                if ($isLocale){
                    push(@ListOfRules, $srcURI." ".$dstURI." ".$ruleType." ".$_.".emc.com");
                }elsif ($isMicrosite){
                    push(@ListOfRules, $srcURI." ".$dstURI." ".$ruleType." ".$_);
                }
                
                $ruleExisting = 0;
                $isMicrosite  = 0;
                $isLocale     = 0;
			}
		}
	}
}

sub recoverConf{
    
    my $date = $_[0];
    my ($day,$month,$year) = split(/-/,$date);
    my $serverLog  = $rrms_logsdir."servers.log";
    my $username;
    my $server;
    my $timestamp  = scalar(localtime(time + 0));
    my $errno;
    my $counter = 0;
    my $concatServers;
    open (SERVLST,$serverList) or die "Can't open the servers list file: $!\n";
    my @SERVERS = <SERVLST>;
    close (SERVLST);
    
    foreach (@SERVERS){
	($username,$server) = split(/@/);
	chomp($username);
        chomp($server);
        $errno = system("ssh -q  $username\@$server 'ls ~/conf_bkp/conf-$day-$month-$year.tar.gz &> /dev/null'");
        $counter += $errno;
        if ($errno != 0){
            $concatServers .= $server." ";
        }
        
        if ($counter > 0){
            open (SERVLOG,">>",$serverLog) or die "Can't open the servers log file: $!\n";
            print SERVLOG "$timestamp - $server - [RESTORE OPERATION] - There is no such backup file for this day\n";
            close (SERVLOG);
            print STDOUT "There is no such backup file for this day on $concatServers\n";
    		unlink $lockfile;
            exit(1);
        }
    }
    
	if ($counter == 0){
		foreach  (@SERVERS){
			($username,$server) = split(/@/);
        		chomp($username);
			chomp($server);
			if ($username eq "root"){
         		       $SUDO = "";
        		}
			print STDOUT "--------------------------------------------\n";
			print STDOUT "Recovering server $server\n";
			print STDOUT "--------------------------------------------\n";
            		print STDOUT "Stopping the Apache instance.\n";
			print STDOUT "Recovering the conf directory from the backup file conf-$day-$month-$year.tar.gz\n";
            		system("ssh -q $username\@$server '$SUDO /sbin/service httpd stop &> /dev/null'");
            		system("ssh -q $username\@$server 'rm -Rf /etc/httpd/conf/* &> /dev/null'");
            		system("ssh -q $username\@$server 'cd / ; tar xfvz ~/conf_bkp/conf-$day-$month-$year.tar.gz &> /dev/null'");
            		print STDOUT "Starting the Apache instance.\n";
            		system("ssh -q $username\@$server '$SUDO /sbin/service httpd start &> /dev/null'");
        	}
	}
    	print STDOUT "\nSuccessfuly recovered the apache configurations to $day-$month-$year\n";
    		unlink $lockfile;
    	exit(0);
}

sub restoreToRevision{
    
	my $revno = $_[0];
	my $errno;
	print STDOUT "Restoring to revision $revno\n";
   	$errno = system("cd $svndir ; svn update -r $revno");
	if ($errno == 0){
        	system("cp -R $svndir $absolute_path.uwconf");
        	system("find $absolute_path.uwconf -type d -name .svn | xargs rm -Rf &> /dev/null");
        	system("cd $absolute_path ; tar cfvz uwconf.tar.gz .uwconf &> /dev/null");
        	system("rm -Rf $absolute_path.uwconf");
        	updateServers();
        	system("rm -Rf $absolute_path/uwconf.tar.gz");
		unlink $lockfile;
        	exit(0);
	}else{
		print STDERR "Error updating servers to SVN revision $revno\n";
		unlink $lockfile;
		exit($errno);
	}
}

sub htmlheader{

    my $timestamp = scalar(localtime(time + 0));
    if ($opt_validate){
        push (@ValidationEmailMessage, "<html><head><title></title></head><body><h3><u>Rules by user $UserName on environment ($envname) on $timestamp</u></h3><ul>");
    }
}

sub htmlfooter{
    if ($opt_validate){
        push (@ValidationEmailMessage, "</ul><center><h7><i>Report generated by rrms v $VERSION</i></h7></center></body></html>");
    }
}

sub Usage{

print "           Version $VERSION\n";
print "           By Khaled Ahmed (SDG Team)\n";
print "           Copyright (C) 2012-2013\n\n";
print "Options: \n";
print "                              username password /from /to [vanity|redirect] domain(s)\n";
print "         [--delete|-d]        username password /rule domain(s)\n";
print "         [--notify]           Send a notification with the performed action(s) to the management (Default = ON)\n";
print "         [--silent]           Don't send email notification\n";
print "         [--deploy]           Deploy the SVN repository to the UW web servers\n";
print "         [--reload]           Reload the UW Apache farm (Can't be used with [--deploy])\n";
print "         [--restore]          Restore the Apache conf to an SVN revision (takes rev # as argument)\n";
print "         [--recover]          Recover the Apache conf to a previous state from server backup files by date (fmt dd-mm-yyyy)\n";
print "         [--env]              Sets the working environment (Environments are defined in the environments.conf file)\n";
print "         [--file]             Provide file path to raw rules for bulk processing\n";
print "         [--excel]            Provide the Excel template for processing\n";
print "         [--inline]           Extract the domain name and rule type from the bulk text file provided by [--file] in the format [http://<domain>/from  /to ruletype]\n";
print "         [--validate]         Validate manipulated rewrite rules\n";
print "         [--version|-v]       Show version.\n";
print "         [--help|-h]          Show this help message.\n\n";
exit (0);
}

__END__
