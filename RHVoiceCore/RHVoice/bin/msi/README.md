# Shared MSI packages

This document explains how RHVoice SAPI5 installer executables share
MSI Packages for Core, Language and Voice, and how to create a
consistent and maintainable series of SAPI5 installs for your voice.

## What goes into a SAPI5.exe for a voice install?

The exe contains your voice data files, wrapped inside an MSI package.  

It must also contain whatever version of the RHVoice language files
that your voice needs. That set of language files is also wrapped in its
own MSI package.

And finally, both a 32- and 64-bit versions of the RHVoice Core TTS,
each in its own MSI package.

## Understanding MSI package versioning.

The four components mentioned above (voice data, language files, and
two versions of the core), all have their own RHVoice versions, and
they all have to be compatible with each other. But, in addition to
taking care of that version control system, you need to be aware of
MSI package version effects. This is in order for you to upgrade your
users, or to supply users who have other voices in the same language
as yours, and who obtained their language files elsewhere than from
you.

When the Microsoft Installer opens a new package, it checks if it already has the contents of this package installed. Here is where problems could arise.  

Every MSI package is assigned a unique package code at build time. If
the package is removed and then rebuilt without any other changes
being introduced, with exactly the same contents as before, the newly
built package file will still have a different package code.

And two packages containing the same version of the same component,
but having different package codes, will cause an installation error.

For example, you are distributing an upgrade of your voice from your
version 4.0 to 4.1. You need to include in the exe the other three
components. Those - the core and the language pack - have not changed.
But we must make sure that we do not create new MSI packages for them.
We do not want the installation to fail because, say, the installer
opens up what looks like a new MSI package for the language, only to
find that it contains the same version of the language files already
installed. And thus the whole install fails. You will learn below how
our exe build script takes care of this.

## Building your voice installers

When you build RHVoice on Windows by executing the `scons` command,
voice installer executables will be created for all the voices as part
of the overall build process.

### Which core MSIs will be used

The MSI packages containing the latest stable version of the core are
published in this repository. They will be used by default.

### MSI packages of languages and voices

This is how the build script will select an appropriate MSI package
for each voice or language. The paths are relative to the root
directory of the main RHVoice repository.

1. Read the version number from the corresponding voice.info or
   language.info file.

2. Look for an MSI package with this version number in the
   bin/msi/local directory. Here the build script expects to find your
   locally saved packages from previous builds. Put here your voice
   packages for reuse, as well as your language packages while the
   language is in development and not considered stable.

3. If no package has been found at step 2, the build script looks in
   the bin/msi/shared directory. Here are the public MSI packages
   shared in this repository: the core and the stable versions of the
   languages.

4. If no package has been found at step 3, the script builds a new one
   and saves it in the build/windows/packages/sapi/msi directory. You
   should copy any new packages you or other developers may need in
   the future from this directory right away, as they may be
   overwritten by a future build.

## Your Responsibility for Voice MSI Package versioning.

As a result, one situation where you must take responsibility is when
you want to give your voice users upgrades to the core or to the
language, and when the voice itself has not changed. You are the one
who must supply the MSI package for the voice. You must not supply a
brand new MSI package for the voice. You must re-use the same MSI
package you last used to deliver the existing voice version to users.
Thus, it is imperative that you save each voice MSI Package that you
distribute. If you do not, and you want to distribute a core or
language update, you will need to ask your users to first uninstall
the voice.

## Your responsibility as language developers.

Language developers, please share your stable language MSI packages by
making a pull request here, so other developers of voices for your
language can create compatible voice installers. We need your language
MSI packages, not just the language files. If you have given a voice
in your language to a SAPI user, and another developer wants to
distribute a different voice, that developer must include the same MSI
package of your language, and not just the same version of your
language files, with their voice, they will need one of your language
MSI packages.
