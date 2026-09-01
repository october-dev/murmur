# Murmur for Omarchy

A minimal Omarchy Quattro bar widget for Murmur. It provides the plugin
manifest, bar entry point, and panel lifecycle required by Omarchy. The panel
is intentionally read-only until Murmur has a reviewed local service protocol.

## Install from this checkout

From the Murmur repository root:

```sh
omarchy plugin add "$PWD/integrations/omarchy" --enable
```

Click **M** in the right side of the Omarchy bar to open the panel. Press
Escape to close it.

## Validate while developing

```sh
PLUGIN_DIR="$PWD/integrations/omarchy"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" \
  "$PLUGIN_DIR/BarWidget.qml" "$PLUGIN_DIR/Panel.qml"
```

After editing an installed copy, refresh discovery with:

```sh
omarchy-shell shell rescanPlugins
```

## Marketplace packaging

The Omarchy marketplace requires `manifest.json`, README, and license at the
root of a public plugin repository. This directory is the canonical source in
the Murmur monorepo. Before marketplace submission it is split into a small
plugin repository, with the repository's Apache-2.0 license copied alongside
these files.

Omarchy plugins run unsandboxed with the user's permissions. The current
scaffold does not launch processes, execute voice actions, or access API keys.
Any future local-service bridge must use a fixed, authenticated protocol and be
reviewed as privileged code.
