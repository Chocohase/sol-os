var plasma = getApiVersion(1);

// Apply Sol Eclipse wallpaper across all screens/desktops
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; i++) {
    var desktop = allDesktops[i];
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "file:///usr/share/wallpapers/SolEclipse/");
}

// Top slim status bar
var topPanel = new Panel();
topPanel.location = "top";
topPanel.height = 32;
topPanel.floating = false;
topPanel.lengthMode = "fill";

var kickoff = topPanel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["Shortcuts"];
kickoff.writeConfig("global", "Alt+F1");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "sol-os-logo");
kickoff.writeConfig("menuLabel", "Sol OS");
kickoff.writeConfig("showActionButtonCaptions", true);

topPanel.addWidget("org.kde.plasma.appmenu");
topPanel.addWidget("org.kde.plasma.panelspacer");
topPanel.addWidget("org.kde.plasma.systemtray");

var digitalClock = topPanel.addWidget("org.kde.plasma.digitalclock");
digitalClock.currentConfigGroup = ["Appearance"];
digitalClock.writeConfig("showDate", true);
digitalClock.writeConfig("dateFormat", "custom");
digitalClock.writeConfig("customDateFormat", "ddd, MMM d |");
digitalClock.writeConfig("use24hFormat", 2);
digitalClock.writeConfig("dateDisplayFormat", "BesideTime");

// Bottom floating dock
var bottomDock = new Panel();
bottomDock.location = "bottom";
bottomDock.floating = true;
bottomDock.alignment = "center";
bottomDock.lengthMode = "fit";
bottomDock.height = 54;

var iconTasks = bottomDock.addWidget("org.kde.plasma.icontasks");
iconTasks.currentConfigGroup = ["General"];
iconTasks.writeConfig("launchers", [
    "applications:steam.desktop",
    "applications:systemsettings.desktop",
    "preferred://browser",
    "applications:org.kde.konsole.desktop",
    "applications:org.kde.dolphin.desktop"
]);
iconTasks.writeConfig("onlyGroupWhenFull", true);

// Bottom-left desktop widgets on primary desktop
if (allDesktops.length > 0) {
    var primaryDesktop = allDesktops[0];
    var screenId = primaryDesktop.screen >= 0 ? primaryDesktop.screen : 0;
    var screenRect = screenGeometry(screenId);

    var marginLeft = 24;
    var bottomClearance = 84;
    var widgetGap = 14;
    var minTopY = 48;

    var cpuWidth = 240;
    var cpuHeight = 160;
    var mediaWidth = 260;
    var mediaHeight = 120;

    var mediaY = Math.round(Math.max(minTopY, screenRect.height - bottomClearance - mediaHeight));
    var cpuY = Math.round(Math.max(minTopY, mediaY - widgetGap - cpuHeight));

    primaryDesktop.addWidget("org.kde.plasma.systemmonitor.cpu", marginLeft, cpuY, cpuWidth, cpuHeight);
    primaryDesktop.addWidget("org.kde.plasma.mediacontroller", marginLeft, mediaY, mediaWidth, mediaHeight);
}
