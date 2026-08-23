#!/usr/bin/env bash
# CI lint gate for the full-localization-web-apps openspec change (sweetrpg/platform):
# fails on new hardcoded user-facing strings in Leaf templates. All user-facing text must
# come from Resources/Localizations/<code>.json via the app's l10n table.
set -u

cd "$(dirname "$0")/.." || exit 1

allowlist='SweetRPG|GitHub|Auth0|Pilgrimage Software'
count=0
checked=0

while IFS= read -r -d '' template; do
    checked=$((checked + 1))
    findings=$(perl -0777 -pe '
    s{<script\b.*?</script>}{}gis;
    s{<style\b.*?</style>}{}gis;
    s{<!--.*?-->}{}gs;
    s{\{\{.*?\}\}}{}gs;
    s{\{%.*?%\}}{}gs;
  ' "$template" | perl -0777 -ne '
    while (/<[^>]*>([^<]*)</g) { print "$1\n" }
    while (/^([^<]+)/mg) { print "$1\n" }
  ' | perl -ne '
    my $line = $_;
    (my $trimmed = $line) =~ s/&[a-zA-Z#0-9]+;/ /g;
    $trimmed =~ s/\s+/ /g;
    $trimmed =~ s/^\s+|\s+$//g;
    next if $trimmed eq q{};
    next if $trimmed =~ /^[\p{P}\p{S}\p{N}\s]*$/;
    print "HARDCODED STRING in '"$template"': $line";
  ' | grep -vE "^HARDCODED STRING in .*(${allowlist})" || true)
    if [ -n "$findings" ]; then
        printf '%s\n' "$findings"
        count=$((count + 1))
    fi
done < <(find . \( -path ./.build -o -path ./node_modules \) -prune -o -name '*.leaf' -print0)

if [ "$count" -gt 0 ]; then
    echo "locale-lint: FAIL - $count template(s) contain hardcoded user-facing strings. Move them into Resources/Localizations/*.json."
    exit 1
fi

echo "locale-lint: PASS (checked ${checked} leaf template(s))"
exit 0
