---
# This document includes simple backmatter for generating PDF documents from
# pandoc markdown.

header-includes: |
  \usepackage[angle=0, opacity=1, scale=1.25, hshift=-0.93cm]{background}
  \usepackage{fancyhdr}
  \usepackage{fullpage}
  \usepackage{fvextra}
  \usepackage{lastpage}
  \usepackage{titling}
  \DefineVerbatimEnvironment{Highlighting}{Verbatim}{xleftmargin=.5cm,breaklines,commandchars=\\\{\}}
  \interfootnotelinepenalty=10000
  \backgroundsetup{contents=\includegraphics{images/orch_internals_bg.pdf}}
  \renewcommand{\headrulewidth}{0pt}
  \pagestyle{fancy}
  \fancyhf{}
  \lfoot{\thetitle}
  \rfoot{Page \thepage~of \pageref{LastPage}}
  \thispagestyle{fancy}
---
