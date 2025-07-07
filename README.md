![icon](images/RunLast.readme.png)

## Description

**RunLast** creates an environment to run commands or shell-scripts after QPKG re-integration during QTS NAS bootup.

This allows you to run scripts dependent on QPKGs during QTS startup.

The aim of this project is to support **all** QNAP NAS models and **all** QTS & QuTS hero versions from v4.0.0 onwards. Please advise if you encounter any errors when running it on your NAS.

## What it does

This package creates two scripts directories in the package installation path:
- `init.d`
- `scripts`

Place your SysV-style scripts in the `init.d` directory. These will be executed with a `start` parameter after NAS startup, and with a `stop` parameter before NAS shutdown.
Scripts in the `scripts` directory will be executed only during startup, and always after the custom `init.d` start script execution.

## Installation

- available in the [MyQNAP repo](https://www.myqnap.org/product/runlast), and can also be installed via the [sherpa](https://github.com/OneCDOnly/sherpa) package manager.


## Notes

- When this package is installed, there's not much to see. Find the package icon and click the 'Open' button to display the current log file - any stdout and stderr from your scripts will be shown here.

- The log file is viewable via your web browser but is not a real web document, so it can change without your browser noticing. Whenever viewing the log, ensure you force a page refresh: CTRL+F5.

- To jump to the `scripts` directory:

```
cd $(getcfg RunLast Scripts_Path -f /etc/config/qpkg.conf)
```

- Or, to jump to the `init.d` directory:

```
cd $(getcfg RunLast SysV_Path -f /etc/config/qpkg.conf)
```

- The source for this project can be found on [GitHub](https://onecdonly.github.io/RunLast/).

- [Changelog](changelog.txt)
