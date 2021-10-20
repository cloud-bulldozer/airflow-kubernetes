from os import environ

def get_git_user():
    git_repo = environ['GIT_REPO']
    git_path = git_repo.split("https://github.com/")[1]
    git_user = git_path.split('/')[0]
    return git_user.lower()