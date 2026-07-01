# create_pipeline_from_yaml catches cyclic target graphs

    Code
      create_pipeline_from_yaml(yaml_file)
    Condition
      Error:
      ! Generated targets pipeline failed {targets} validation: graph contains a cycle.