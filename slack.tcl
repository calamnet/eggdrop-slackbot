##############################################################################
#
# Slack Functionality
# https://slack.com/
#
# @author Jason Roman <j@jayroman.com>
#
##############################################################################

# rest package also includes the http and json packages
package require rest
package require tls
package require json::write
package require yaml

# add https support - force TLS, no longer use SSLv3 (POODLE exploit)
http::register https 443 [list ::tls::socket -tls1 true -ssl2 false -ssl3 false]

# do not add newlines in json - keep it condensed
json::write indented 0

# define the slack namespace and all variables that must be defined and non-empty in config.yml
namespace eval slack {

    namespace eval webhook {
        variable url {}
        variable unfurl_links {true}
    }

    namespace eval channel {
        variable mapping {}
        variable command_prefix {}
    }

    set optional {::slack::channel::command_prefix}
}


# processes the slack configuration file
#
# @return true|exit - 1 on success, exit on failure
proc ::slack::processConfig {} {

    global SlackbotScriptDir

    # load config.yml in the script's directory into the config dictionary
    set config [yaml::yaml2dict -file [file join $SlackbotScriptDir config.yml]]

    # loop through all config values and set their corresponding namespace variable
    dict for {topLevelKey subDict} [dict get $config] {
        dict for {key value} [dict get $subDict] {

            # check if the key is previously defined in our namespace declaration; if so, set its value
            if {[info exists ::slack::${topLevelKey}::$key]} {
                set ::slack::${topLevelKey}::$key $value
            }
        }
    }

    # all required namespace parameters must be defined with a non-empty value - exit if any are missing
    set missingKeys {}

    # loops through each sub-namespace here (::slack::*) and every declared namespace variable
    foreach {subNamespaceName} [listns slack] {
        foreach {key} [listnsvars $subNamespaceName] {

            # add to the missing keys if the value is blank and the key is required
            if {[subst $$key] == "" && [lsearch $::slack::optional $key] == -1} {
                lappend missingKeys $key
            }
        }
       
    }

    # notify the user of what required values are missing and stop execution
    if {[llength $missingKeys]} {
        puts "Undefined configuration variables: \n[join $missingKeys \n]"
        exit
    }

    return 1
}

# check if a mapping exists from the given irc channel to a corresponding slack channel
#
# @param string channel
# @return bool
proc ::slack::channel::mappingExists {channel} {
    return [dict exists $slack::channel::mapping $channel]
}

# retrieve the name of the slack channel that correspondings to the irc channel
#
# @param string channel
# @return string|false - slack channel if exists, 0 if it does not
proc ::slack::channel::ircToSlack {channel} {

    if {[::slack::channel::mappingExists $channel]} {
        return [dict get $slack::channel::mapping $channel]
    }

    return 0
}

# check if the given irc message is a command
#
# @param string msg
# @return bool
proc ::slack::channel::isCommand {msg} {
    # if the message starts with any of the specified prefixes, it is considered a command
    foreach {prefix} [split $::slack::channel::command_prefix ","] {
        if {[string first $prefix $msg] == 0} {
            return 1
        }
    }

    return 0
}


# process the configuration file to setup the slack parameters
::slack::processConfig

# set the REST command to push data to slack via the webhook
set slack(push) {
    url $::slack::webhook::url
    method post
    req_args { payload: }
}

# make sure the variables are substituted with their appropriate values
set slack(push) [subst $slack(push)]

# create the interface for all slack rest commands
rest::create_interface slack
