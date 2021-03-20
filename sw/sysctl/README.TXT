USAGE:

30mhz with both L2 and L1 cache disabled would be:

    sysctl sys 30mhz l2- l1- 

This would restore normal operation:

    sysctl menu

valid options:

    menu (default)
    sys or sysctl 
    90 or 90Mhz (default)
    56 or 56Mhz
    30 or 30Mhz
    15 or 15Mhz
    L1+ (default)
    L1-
    L2+ (default)
    L2-
	
