![icon](images/runlast-cs-b.png)

## Description

**RunLast** creates an environment to run commands or shell-scripts after QPKG re-integration during QTS NAS bootup.

This allows you to run scripts dependent on QPKGs during QTS startup.

## What it does

This package creates a scripts directory in the package installation path. Your scripts must be placed here. When this QPKG starts, it processes each script, storing any stdout and stderr to a log, viewable via the QTS UI.

## How to install

- It's available in the [Qnapclub Store!](https://qnapclub.eu/en/qpkg/690)

- [Click here](https://qnapclub.eu/en/howto/1) to learn how to add the **Qnapclub Store** as an App Center repository in QTS.


## Notes

- When this package is installed, there's not much to see. Find the package icon and click the 'Open' button to display the current log file - any output from your scripts will be shown here.

- The log is viewable via your web browser but is not a real web document, so it can change without your browser noticing. Whenever viewing the log, ensure you force a page refresh: CTRL+F5.


- [Changelog](changelog.txt)
