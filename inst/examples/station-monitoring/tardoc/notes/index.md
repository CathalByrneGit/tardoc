**Weekly station health check.** Reads each logger's temperature export, drops
readings outside the probe's rated range, then fits a drift model and flags any
station whose probe needs servicing. The result is the station report at the end
of the pipeline.

Start with `clean`: everything downstream depends on its range filter. The data
are synthetic — 400 readings across six stations — so none of these numbers is
real.

This text is `tardoc/notes/index.md` in the example project. It is yours to write
and tardoc never overwrites it; it appears here, under the title, on the home page.
