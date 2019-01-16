# sip call notifier
A voip/sip client phone running as a linux service that connects to your provider and informs android tv (sony bravia, fire tv etc) about incomming calls.

It also blocks calls via a blacklist csv file, the file is a single column csv.

You can export your contacts from Goolle Contacts as a contacts.csv file and provide it to the linux service, it will than notify your androit tv or fire tv about your incomming call by looking up the numbers in the csv.

All calls and logs are written in log file located at /var/logs/calls.log (you may change that).

The config file is pretty straight forward and includes some minor settings for your provider and contacts.csv file location and android tv IP.

The programm is solely written in perl but can be compiled as a standard executable by using perl packer.

A sqlite database is initialized in memory in order to load contacts.cvs and blacklist.

The message to android tv is send by using nfa, a Go command line app to send notifications to Notifications for Android TV / Notifications for Fire TV that can be found here https://github.com/robbiet480/nfa , you may build by simply running "go get github.com/robbiet480/nfa" and get it from your golang bin dir.

Notifications for Android TV / Notifications for Fire TV  must be installed on on your TV in order for the notification to be displayed, you may find it on Google Play. Once installed you have to open the application once in order for the app to be initialized on the tv so it can accept notifications.

Distribution is packaged as a debian package (.deb) file and includes an init script and the golang nfa binary, it also includes the binary version of sipcallnotifier (arch i386) and the perl version(sipcallnotfier.perl) for ease of use, in case you want to make changes. If this is the case do not forget to change your init script to run sipcallnotfier.pl instead of sipcallnotifier.

Cheers
GB

