
-- LM -- Dataset -- 4/6/16 --



function Dataset(list, isFilelist, computeFramestats, decode)
  
  -- initialization
  local dataset = {}
  local flog, plog, log
  
  -- logs
  if not decode then
    flog = logroll.file_logger(settings.outputFolder .. settings.logFolder .. '/' .. list .. '.log')
    plog = logroll.print_logger()
    log = logroll.combine(flog, plog)
  end

  -- log & timer
  if not decode then
    log.info('Preparing dataset: ' .. list)
  end
  local begin = sys.clock()
  
  -- dataset initialization
  dataset.index = {}
  dataset.nSamplesList = {}
  dataset.cache = {}
  dataset.framestats = {}
  dataset.nSamples = 0
  
  -- initialize sample count
  local totalSamples = 0
  
  -- check if input is file or filelist and get file name(s)
  local filelist = {}
  if isFilelist then
    filelist = readFilelist(settings.listFolder .. list)
  else
    table.insert(filelist, list)
  end
  
  -- initialize framestats
  if not decode then
    for i = 1, settings.outputSize, 1 do
      dataset.framestats[i] = 0
    end
  end
  
  -- read data from files
  for file = 1, #filelist, 1 do  
    
    -- log
    if not decode then
      flog.info('Processing file: ' .. filelist[file])
    end
    
    local nSamples, sampPeriod, sampSize, parmKind, fvec, viewRefs
    
    -- read input files
    if settings.inputView > 0 then
      nSamples, sampPeriod, sampSize, parmKind, fvec, viewRefs = readView(filelist[file], true)
    else
      nSamples, sampPeriod, sampSize, parmKind, fvec = readInputs(filelist[file])
    end
    
    -- read refs files
    local references
    if not decode then 
      if settings.sameFolder == 0 then
        filelist[file] = filelist[file]:gsub(settings.parPath, settings.refPath)
      end

      if settings.inputView > 0 then
        references = viewRefs
      else
        references = readRefs(filelist[file], nSamples)
      end    
      
      -- compute framestats
      if computeFramestats then
        for i = 1, references:size(1), 1 do
          if references[i] < settings.outputSize then
            dataset.framestats[references[i]+1] = dataset.framestats[references[i]+1] + 1
          end
        end
      end
    end

    -- clone borders
    if settings.cloneBorders == 1 then
      fvec = cloneBordersInputs(fvec)
      if not decode then 
        references = cloneBordersRefs(references)
      end
      nSamples = nSamples + settings.seqL + settings.seqR
    end
      
    -- apply CMS
    if settings.applyCMS == 1 then
      applyCMS(fvec, nSamples)
    end    
    
    -- store data to memory
    fvec = fvec:view(fvec:size(1) * settings.inputSize)
    table.insert(dataset.cache, {inp = fvec, out = references})
    
    -- save counts of samples per file to table
    nSamples = nSamples - settings.seqL - settings.seqR
    table.insert(dataset.nSamplesList, nSamples)
    
    -- calculate total samples
    if nSamples >= 1 then
      totalSamples = totalSamples + nSamples
    end
    
  end

  -- prepare tensors for data for training
  dataset.index.file = torch.Tensor(totalSamples):int()    -- tensor -> frames vs. file
  dataset.index.pos = torch.Tensor(totalSamples):int()     -- tensor -> frames vs. position in file
  
  -- fill tensors accordingly to allow training
  for ll = 1, #dataset.nSamplesList, 1 do   
    local nSamples = dataset.nSamplesList[ll]
    if nSamples >= 1 then     -- sanity check
      i = settings.seqL
      dataset.index.file:narrow(1, dataset.nSamples + 1, nSamples):fill(ll)               -- fe [1 1 1 2 2 2 2 2]
      dataset.index.pos:narrow(1, dataset.nSamples + 1, nSamples):apply(function(x)       -- fe [1 2 3 1 2 3 4 5] + seqL
        i = i + 1
        return i
      end)
      -- compute final number of samples
      dataset.nSamples = dataset.nSamples + nSamples   
    end
  end  
  
  -- prepare mean & std tensors
  local mean = settings.mean:repeatTensor(settings.seqL + settings.seqR + 1)
  local std = settings.std:repeatTensor(settings.seqL + settings.seqR + 1)
  
  -- log time
  if not decode then
    log.info('Dataset prepared in ' .. sys.clock() - begin)
  end
  
  -- return number of samples
  function dataset:size() 
    return self.nSamples
  end
  
  -- get frame + surroundings and ref
  setmetatable (dataset, {__index = function (self, i)
    -- identify file    
    local fileid = dataset.index.file[i]
    
    -- load file data
    local currentInput = self.cache[fileid].inp
    local currentOutput = self.cache[fileid].out
    
    -- find the indices of asked data
    local startIndex = (dataset.index.pos[i] - settings.seqL - 1) * settings.inputSize + 1
    local endIndex = startIndex + (settings.seqR + 1 + settings.seqL) * settings.inputSize - 1
    
    -- clone the asked data   
    local inp = currentInput[{{startIndex, endIndex}}]:clone()   
    
    -- normalize
    inp:add(-mean)
    inp:cdiv(std) 

    -- prepare the output
    local out
    if not decode then
      out = (currentOutput[dataset.index.pos[i]] + 1)
    end
    
    -- return the asked data
    return {inp = inp, out = out}
    
    end
  })
  
  return dataset
  
end


