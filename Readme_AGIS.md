# 1. 安装依赖
pip install -r requirements.txt

# 2. 配置数据库
在.env文件中配置数据库和openai的api_key以及openai的api_base

# 3. 运行
python src/main.py -path [项目路径（相对路径）] -id [希望在数据库中展示的project id]

# 4. 查看数据库
当前agis需求的表结构如下：
affected_files	range	title	content
对应数据库中的：
affected_files	range	title	result 

# 5. 如何判断已经扫描完成
执行以下sql：
```
SELECT CASE 
    WHEN NOT EXISTS (
        SELECT 1 
        FROM project_tasks_amazing_prompt 
        WHERE project_id = '[输入project id名字]' 
        AND (result IS NULL OR result = '')
    ) THEN 'Completed'
    ELSE 'Not Completed'
END AS task_status;
```

查询返回结果task_status列为Completed时，表示扫描完成，为Not Completed时，表示未完成

# 6. 考虑到后面的多种数据需求，暂时没有去掉无关的列