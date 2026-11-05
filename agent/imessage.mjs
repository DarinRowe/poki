#!/usr/bin/env node
import { MessageSource } from './message-source.mjs';
import { runMessageWorker, reportChannelError } from './message-worker.mjs';

runMessageWorker('bluebubbles', MessageSource).catch(reportChannelError);
