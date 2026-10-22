# R 4.6.1 with the package's dependencies as binaries from Posit Package Manager (rocker sets the repository), then
# the package itself. Used locally (R is not installed on the host) and for the analysis in CI.
FROM rocker/r-ver:4.6.1
RUN install2.r --error --skipinstalled arrow jsonlite testthat covr lintr roxygen2 \
 && rm -rf /tmp/downloaded_packages
COPY bankwarn /src/bankwarn
RUN R CMD INSTALL /src/bankwarn
RUN useradd --system --uid 10001 --create-home analyst
USER analyst
