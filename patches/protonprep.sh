#!/bin/bash

### (1) PREP SECTION ###

    #WINE STAGING
    cd wine-staging
    git reset --hard HEAD
    git clean -xdf

    # revert pending pulseaudio changes
    git revert --no-commit 183fd3e089b170d5b7405a80a23e81dc7c4dd682

    # reenable pulseaudio patches
    patch -Np1 < ../patches/wine-hotfixes/staging/staging-reenable-pulse.patch
    patch -RNp1 < ../patches/wine-hotfixes/staging/staging-pulseaudio-reverts.patch

    # protonify syscall emulation
    patch -Np1 < ../patches/wine-hotfixes/staging/protonify_stg_syscall_emu.patch

    # partial revert to fix steamclient
    patch -RNp1 < ../patches/wine-hotfixes/staging/staging-server-default-integrity.patch
    cd ..

### END PREP SECTION ###

### (2) WINE PATCHING ###

    cd wine
    git reset --hard HEAD
    git clean -xdf

### (2-1) PROBLEMATIC COMMIT REVERT SECTION ###


    # https://bugs.winehq.org/show_bug.cgi?id=49990
    echo "revert bd27af974a21085cd0dc78b37b715bbcc3cfab69 which breaks some game launchers and 3D Mark"
    git revert --no-commit bd27af974a21085cd0dc78b37b715bbcc3cfab69

    echo "this breaks hitman 2"
    git revert --no-commit 8f37560faf130eecd137c14db39555952edf9aaa

    echo "temporary pulseaudio reverts"
    git revert --no-commit e309bad98c736d3409b5ceaffa77486a73c1f80b
    git revert --no-commit 7d60d0d7bbc0138133d1968dc3802e2e79ab5b32
    git revert --no-commit 4303e753137d0b44cff4f9261d10ef86d57016f2
    git revert --no-commit 2e64d91428757eaa88475b49bf50922cda603b59
    git revert --no-commit f77af3dd6324fadaf153062d77b51f755f71faea
    git revert --no-commit ce151dd681fe5ee80daba96dce12e37d6846e152
    git revert --no-commit 77813eb7586779df0fb3b700000a17e339fd5ce3
    git revert --no-commit d8e9621cfad50596378283704dfb1e6926d77ed8
    git revert --no-commit a4149d53f734bf898087e22170eab5bed9a423d1
    git revert --no-commit b4c7823bbb6a792098131f5572506784c8ed0f35
    git revert --no-commit 70f59eb179d6a1c1b4dbc9e0a45b5731cd260793
    git revert --no-commit e19d97ff4e2f5a7800d6df77b8acce95130b84c3
    git revert --no-commit 4432b66e372caf0096df56f45502d7dea1f1800c
    git revert --no-commit 6a6296562f536ed10d221f0df43ef30bbd674cb2
    git revert --no-commit aba40bd50a065b3ac913dbc1263c38535fb5d9e7
    git revert --no-commit bf74f36350c92daae84623dc0bd0530c212bb908
    git revert --no-commit 1518e73b23211af738ae448a80466c0199f24419
    git revert --no-commit 44e4132489c28b429737be022f6d4044c5beab3e
    git revert --no-commit a6131544e87c554f70c21a04fb4697d8e1f508d5
    git revert --no-commit 80b996c53c767fef4614f097f14c310285d9c081
    git revert --no-commit 459e911b653c7519a335661a6c0b0894e86d2f1a
    git revert --no-commit 42d826bc8c1d625ed2985ff06c2cd047209a1916
    git revert --no-commit 30c17619e5401618122ca330cf0909f49b170a59
    git revert --no-commit af84907ccad3e28f364ecfaa75ccb5fedf7f5a42
    git revert --no-commit a5997bece730beb8ab72d66b824ed2a1cb92c254
    git revert --no-commit 24a7c33fc1ad6dbab489284cfb6dba4130297ddb
    git revert --no-commit 8cb88173d87efedce8c345beea05641f5617d857
    git revert --no-commit 505d4b8b14913f3abd362bf27272e6b239cb6ce4
    git revert --no-commit 638455136b4d30b853b02b77a2f33dc61c60b267
    git revert --no-commit 13cac6287c454146eff73aabc4b92b5c8f76d4df
    git revert --no-commit d7b957654d4739b8dd07c91f051b7940f416ef42
    git revert --no-commit 8ea23d0d44ced0ce7dadc9b2546cbc56f6bce364
    git revert --no-commit 0b0ae164f4ccebf4b5bc1bb1529a90786d2d5941
    git revert --no-commit 131b7fd5e16a3da17aed28e86933074c5d663d9f
    git revert --no-commit 8060e56b26add8eafffb211119798569ea3188ff
    git revert --no-commit bca0706f3a93fa0a57f4dbdc6ae541e8f25afb34
    git revert --no-commit b1ddfca16e4696a52adf2bdd8333eeffb3c6170c
    git revert --no-commit a5d4079c8285c10ab2019c9fd9d19a6b22babb76
    git revert --no-commit ebd344f2922f4044117904e024a0a87576a3eff1
    git revert --no-commit 0eeefec6c56084a0677403aee46493e2c03a1dca
    git revert --no-commit 5477f2b0156d16952a286dd0df148c2f60b71fe6
    git revert --no-commit fa097243e06b3855a240c866a028add722025ead
    git revert --no-commit 8df72bade54d1ef7a6d9e79f20ee0a2697019c13
    git revert --no-commit e264ec9c718eb66038221f8b533fc099927ed966
    git revert --no-commit d3673fcb034348b708a5d8b8c65a746faaeec19d

    # restore e309bad98c736d3409b5ceaffa77486a73c1f80b and
    # 7d60d0d7bbc0138133d1968dc3802e2e79ab5b32 without winepulse
    # bits to prevent breakage elsewhere.
    patch -Np1 < ../patches/wine-hotfixes/staging/wine-pulseaudio-fixup.patch

### END PROBLEMATIC COMMIT REVERT SECTION ###


### (2-2) WINE STAGING APPLY SECTION ###

    # these cause window freezes/hangs with origin
    # -W winex11-_NET_ACTIVE_WINDOW \
    # -W winex11-WM_WINDOWPOSCHANGING \

    # this needs to be disabled of disabling the winex11 patches above because staging has them set as a dependency.
    # -W imm32-com-initialization
    # instead, we apply it manually:
    # patch -Np1 < ../patches/wine-hotfixes/imm32-com-initialization_no_net_active_window.patch

    # This is currently disabled in favor of a rebased version of the patchset
    # which includes fixes for red dead redemption 2
    # -W bcrypt-ECDHSecretAgreement \

    # This was found to cause hangs in various games
    # Notably DOOM Eternal and Resident Evil Village
    # -W ntdll-NtAlertThreadByThreadId

    echo "applying staging patches"
    ../wine-staging/patches/patchinstall.sh DESTDIR="." --all \
    -W winex11-_NET_ACTIVE_WINDOW \
    -W winex11-WM_WINDOWPOSCHANGING \
    -W imm32-com-initialization \
    -W bcrypt-ECDHSecretAgreement \
    -W ntdll-NtAlertThreadByThreadId \
    -W dwrite-FontFallback

    # apply this manually since imm32-com-initialization is disabled in staging.
    patch -Np1 < ../patches/wine-hotfixes/staging/imm32-com-initialization_no_net_active_window.patch

    patch -Np1 < ../patches/wine-hotfixes/staging/mfplat_dxgi_stub.patch

    echo "applying staging Compiler_Warnings revert for steamclient compatibility"
    # revert this, it breaks lsteamclient compilation
    patch -RNp1 < ../wine-staging/patches/Compiler_Warnings/0031-include-Check-element-type-in-CONTAINING_RECORD-and-.patch

### END WINE STAGING APPLY SECTION ###

### (2-4) PROTON PATCH SECTION ###

    echo "applying __wine_make_process_system_restore revert for steamclient compatibility"
    # revert this, it breaks lsteamclient compilation
    patch -RNp1 < ../patches/wine-hotfixes/steamclient/__wine_make_process_system_restore.patch

    echo "steamclient swap"
    patch -Np1 < ../patches/proton/08-proton-steamclient_swap.patch

    echo "protonify"
    patch -Np1 < ../patches/proton/10-proton-protonify_staging.patch

    echo "protonify-audio"
    patch -Np1 < ../patches/proton/11-proton-pa-staging.patch

    echo "steam bits"
    patch -Np1 < ../patches/proton/12-proton-steam-bits.patch

    echo "mouse focus fixes"
    patch -Np1 < ../patches/proton/38-proton-mouse-focus-fixes.patch

    echo "fullscreen hack"
    patch -Np1 < ../patches/proton/41-valve_proton_fullscreen_hack-staging-tkg.patch

    echo "proton font patches"
    patch -Np1 < ../patches/proton/51-proton_fonts.patch

### END PROTON PATCH SECTION ###

### (2-5) WINE HOTFIX SECTION ###

    echo "mfplat additions"
    patch -Np1 < ../patches/wine-hotfixes/mfplat/mfplat-godfall-hotfix.patch

    # fixes witcher 3, borderlands 3, rockstar social club, and a few others
    echo "heap allocation hotfix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-remi_heap_alloc.patch

    echo "uplay broken rendering hotfix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-uplay_render_fix.patch

    echo "msfs2020 hotfix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-msfs2020.patch

#    disabled, still horribly broken
#    patch -Np1 < ../patches/wine-hotfixes/testing/wine_wayland_driver.patch


### END WINE HOTFIX SECTION ###

### (2-6) WINE PENDING UPSTREAM SECTION ###

    echo "BF4 ping fix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-bf4_ping.patch

    echo "riftbreaker fix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-riftbreaker.patch

    # https://bugs.winehq.org/show_bug.cgi?id=51596
    echo "winelib fix"
    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-winelib.patch

#    disabled, currently breaks more than one controller being able to be used.
#    echo "winebus fix"
#    patch -Np1 < ../patches/wine-hotfixes/pending/hotfix-winebus.patch

### END WINE PENDING UPSTREAM SECTION ###


### (2-7) WINE CUSTOM PATCHES ###


### END WINE CUSTOM PATCHES ###
### END WINE PATCHING ###
